const test = require("node:test");
const assert = require("node:assert");
const Module = require("module");

// Self-contained controller tests with the Mongoose models stubbed via the
// require cache, so no live MongoDB is needed. These prove the HTTP handlers are
// server-authoritative: access is decided by the device grant, and a caller
// asserting a caregiver role on the request gets NO extra authority.

function makeRes() {
  return {
    statusCode: null,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

// Load the caregiver controller with Device/Event/User/CaregiverGrant stubbed.
// `seed` provides the in-memory fixtures the stubs serve.
function withStubbedController(seed, run) {
  const devicePath = require.resolve("../models/Device");
  const eventPath = require.resolve("../models/Event");
  const userPath = require.resolve("../models/User");
  const grantPath = require.resolve("../models/CaregiverGrant");
  const ctrlPath = require.resolve("../controllers/caregiver.controller");

  const paths = [devicePath, eventPath, userPath, grantPath, ctrlPath];
  const saved = {};
  for (const p of paths) saved[p] = require.cache[p];

  const devices = (seed.devices || []).map((d) => ({
    ...d,
    isOnline: () => false,
  }));
  const users = new Map((seed.users || []).map((u) => [u.user_id, u]));
  const grantWrites = [];

  function stub(path, exports) {
    const m = new Module(path, module);
    m.exports = exports;
    m.loaded = true;
    require.cache[path] = m;
  }

  stub(devicePath, {
    findOne: async (q) => devices.find((d) => d.device_id === q.device_id) || null,
    find: async (q) =>
      devices.filter(
        (d) =>
          (q.caregiver_id === undefined || d.caregiver_id === q.caregiver_id) &&
          (q.isActive === undefined || d.isActive === q.isActive)
      ),
  });
  stub(eventPath, {
    find: () => ({ sort: () => ({ limit: async () => [] }) }),
    countDocuments: async () => 0,
    aggregate: async () => [],
  });
  class StubUser {
    constructor(doc) {
      Object.assign(this, doc);
    }
    async save() {
      users.set(this.user_id, this);
      return this;
    }
    static async findOne(q) {
      return users.get(q.user_id) || null;
    }
  }
  stub(userPath, StubUser);
  stub(grantPath, {
    findOneAndUpdate: async (filter, update) => {
      grantWrites.push(update);
      return update;
    },
    updateMany: async () => ({}),
  });

  delete require.cache[ctrlPath];
  const controller = require(ctrlPath);

  return Promise.resolve(run({ controller, devices, users, grantWrites })).finally(() => {
    for (const p of paths) {
      if (saved[p]) require.cache[p] = saved[p];
      else delete require.cache[p];
    }
    delete require.cache[ctrlPath];
  });
}

// ============================================
// GTM-507 — caregiver read endpoints
// ============================================

test("summary endpoint: caregiver WITHOUT a grant is denied (403)", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: null, isActive: true }] },
    async ({ controller }) => {
      const res = makeRes();
      // Caller asserts the caregiver role on the request — it must NOT help.
      await controller.getCaregiver_A_device_summery(
        { params: { device_id: "D1" }, user_id: "attacker", user_role: "caregiver" },
        res
      );
      assert.strictEqual(res.statusCode, 403);
    }
  );
});

test("summary endpoint: caregiver WITH an accepted grant is allowed (200)", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: "cg_1", isActive: true }] },
    async ({ controller }) => {
      const res = makeRes();
      await controller.getCaregiver_A_device_summery(
        { params: { device_id: "D1" }, user_id: "cg_1", user_role: "user" },
        res
      );
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.body.device.device_id, "D1");
    }
  );
});

test("summary endpoint: unknown device is 404", async () => {
  await withStubbedController({ devices: [] }, async ({ controller }) => {
    const res = makeRes();
    await controller.getCaregiver_A_device_summery(
      { params: { device_id: "NOPE" }, user_id: "cg_1", user_role: "caregiver" },
      res
    );
    assert.strictEqual(res.statusCode, 404);
  });
});

test("search endpoint: a user cannot self-assign caregiver authority over a device they don't own", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: "cg_1", isActive: true }] },
    async ({ controller }) => {
      const res = makeRes();
      // 'attacker' is neither owner nor granted caregiver, but claims the role.
      await controller.searchDeviceById(
        { query: { device_id: "D1" }, user_id: "attacker", user_role: "caregiver" },
        res
      );
      assert.strictEqual(res.statusCode, 403);
    }
  );
});

test("list endpoint: only owner-granted devices are returned, role assertion ignored", async () => {
  await withStubbedController(
    {
      devices: [
        { device_id: "D1", user_id: "owner_1", caregiver_id: "cg_1", isActive: true },
        { device_id: "D2", user_id: "owner_2", caregiver_id: "cg_OTHER", isActive: true },
      ],
    },
    async ({ controller }) => {
      const res = makeRes();
      await controller.getAllCaregiverDevices(
        { user_id: "cg_1", user_role: "caregiver" },
        res
      );
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.body.total_devices, 1);
      assert.strictEqual(res.body.devices[0].device_id, "D1");
    }
  );
});

// ============================================
// GTM-507 — granting a caregiver is owner-only
// ============================================

test("claim endpoint: non-owner cannot grant a caregiver (403)", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: null, isActive: true }] },
    async ({ controller }) => {
      const res = makeRes();
      await controller.claimDeviceForCaregiver(
        { body: { device_id: "D1", caregiver_id: "cg_1" }, user_id: "not_owner" },
        res
      );
      assert.strictEqual(res.statusCode, 403);
    }
  );
});

test("claim endpoint: owner grants caregiver and an accepted grant is recorded", async () => {
  await withStubbedController(
    {
      devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: null, isActive: true, save: async function () {} }],
      users: [],
    },
    async ({ controller, devices, grantWrites }) => {
      // Give the seeded device a save() since the handler persists it.
      devices[0].save = async function () {};
      const res = makeRes();
      await controller.claimDeviceForCaregiver(
        { body: { device_id: "D1", caregiver_id: "cg_1" }, user_id: "owner_1" },
        res
      );
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(devices[0].caregiver_id, "cg_1");
      assert.strictEqual(grantWrites.length, 1);
      assert.strictEqual(grantWrites[0].status, "accepted");
      assert.strictEqual(grantWrites[0].patientUserId, "owner_1");
    }
  );
});

test("claim endpoint: cannot assign yourself as caregiver", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: null, isActive: true }] },
    async ({ controller }) => {
      const res = makeRes();
      await controller.claimDeviceForCaregiver(
        { body: { device_id: "D1", caregiver_id: "owner_1" }, user_id: "owner_1" },
        res
      );
      assert.strictEqual(res.statusCode, 400);
    }
  );
});
