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
  // In-memory grant store keyed by _id, seeded for accept/revoke tests.
  const grants = new Map(
    (seed.grants || []).map((g) => [String(g._id), g])
  );

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
      // Return a doc-like with save() so handlers that re-persist still work,
      // and stash it in the store so a later findById can retrieve it.
      const doc = {
        _id: `grant_${grantWrites.length}`,
        ...update,
        save: async function () {
          grants.set(String(this._id), this);
          return this;
        },
      };
      grants.set(String(doc._id), doc);
      return doc;
    },
    findOne: async (q) => {
      for (const g of grants.values()) {
        if (
          (q.deviceId === undefined || g.deviceId === q.deviceId) &&
          (q.caregiverUserId === undefined ||
            g.caregiverUserId === q.caregiverUserId)
        ) {
          return g;
        }
      }
      return null;
    },
    findById: async (id) => grants.get(String(id)) || null,
    // find() returns a sort()-able chain that resolves to the matching grants,
    // mirroring the Mongoose query the listCaregiverGrants handler uses.
    find: (q = {}) => {
      const matches = [...grants.values()].filter(
        (g) =>
          (q.deviceId === undefined || g.deviceId === q.deviceId) &&
          (q.caregiverUserId === undefined ||
            g.caregiverUserId === q.caregiverUserId) &&
          (q.patientUserId === undefined ||
            g.patientUserId === q.patientUserId) &&
          (q.status === undefined || g.status === q.status)
      );
      return { sort: async () => matches };
    },
    updateMany: async () => ({}),
  });

  delete require.cache[ctrlPath];
  const controller = require(ctrlPath);

  return Promise.resolve(run({ controller, devices, users, grantWrites, grants })).finally(() => {
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

test("invite endpoint: owner invites caregiver and a PENDING grant is recorded (no access yet)", async () => {
  await withStubbedController(
    {
      devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: null, isActive: true, save: async function () {} }],
      users: [],
    },
    async ({ controller, devices, grantWrites }) => {
      const res = makeRes();
      await controller.claimDeviceForCaregiver(
        { body: { device_id: "D1", caregiver_id: "cg_1" }, user_id: "owner_1" },
        res
      );
      assert.strictEqual(res.statusCode, 200);
      // Two-sided consent: device.caregiver_id is NOT set on invite.
      assert.strictEqual(devices[0].caregiver_id, null);
      assert.strictEqual(grantWrites.length, 1);
      assert.strictEqual(grantWrites[0].status, "pending");
      assert.strictEqual(grantWrites[0].patientUserId, "owner_1");
      assert.strictEqual(grantWrites[0].invitedBy, "owner_1");
    }
  );
});

test("invite endpoint: re-inviting an already-accepted relationship is a sane no-op (200, stays accepted)", async () => {
  await withStubbedController(
    {
      devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: "cg_1", isActive: true, save: async function () {} }],
      grants: [
        {
          _id: "g_live",
          deviceId: "D1",
          patientUserId: "owner_1",
          caregiverUserId: "cg_1",
          status: "accepted",
          save: async function () {},
        },
      ],
    },
    async ({ controller, grantWrites }) => {
      const res = makeRes();
      await controller.claimDeviceForCaregiver(
        { body: { device_id: "D1", caregiver_id: "cg_1" }, user_id: "owner_1" },
        res
      );
      assert.strictEqual(res.statusCode, 200);
      // No new pending invite was written over the live grant.
      assert.strictEqual(grantWrites.length, 0);
      assert.strictEqual(res.body.grant.status, "accepted");
    }
  );
});

// ============================================
// Two-sided consent — pending authorizes nothing; accept grants; revoke cuts.
// ============================================

test("pending grant authorizes NOTHING: caregiver read is denied (403) before acceptance", async () => {
  await withStubbedController(
    {
      // Owner invited cg_1 but device.caregiver_id is still null (pending).
      devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: null, isActive: true }],
      grants: [
        {
          _id: "g1",
          deviceId: "D1",
          patientUserId: "owner_1",
          caregiverUserId: "cg_1",
          status: "pending",
        },
      ],
    },
    async ({ controller }) => {
      const res = makeRes();
      await controller.getCaregiver_A_device_summery(
        { params: { device_id: "D1" }, user_id: "cg_1" },
        res
      );
      assert.strictEqual(res.statusCode, 403);
    }
  );
});

test("accept endpoint: only the invited caregiver can accept (others 403)", async () => {
  await withStubbedController(
    {
      devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: null, isActive: true, save: async function () {} }],
      grants: [
        { _id: "g1", deviceId: "D1", patientUserId: "owner_1", caregiverUserId: "cg_1", status: "pending", save: async function () {} },
      ],
    },
    async ({ controller }) => {
      // Owner tries to accept on the caregiver's behalf — forbidden.
      const res1 = makeRes();
      await controller.acceptCaregiverGrant(
        { params: { id: "g1" }, user_id: "owner_1" },
        res1
      );
      assert.strictEqual(res1.statusCode, 403);

      // Unrelated user — forbidden.
      const res2 = makeRes();
      await controller.acceptCaregiverGrant(
        { params: { id: "g1" }, user_id: "attacker" },
        res2
      );
      assert.strictEqual(res2.statusCode, 403);
    }
  );
});

test("accept endpoint: caregiver accepts a pending invite -> access granted (200, device mirrored)", async () => {
  await withStubbedController(
    {
      devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: null, isActive: true, save: async function () {} }],
      users: [{ user_id: "cg_1", caregiving_device_ids: [], save: async function () {} }],
      grants: [
        { _id: "g1", deviceId: "D1", patientUserId: "owner_1", caregiverUserId: "cg_1", status: "pending", save: async function () {} },
      ],
    },
    async ({ controller, devices }) => {
      const res = makeRes();
      await controller.acceptCaregiverGrant(
        { params: { id: "g1" }, user_id: "cg_1" },
        res
      );
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.body.grant.status, "accepted");
      // device.caregiver_id is mirrored ONLY now -> reads become authorized.
      assert.strictEqual(devices[0].caregiver_id, "cg_1");
    }
  );
});

test("state machine: accepting a revoked grant is rejected (409 illegal transition)", async () => {
  await withStubbedController(
    {
      devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: null, isActive: true }],
      grants: [
        { _id: "g1", deviceId: "D1", patientUserId: "owner_1", caregiverUserId: "cg_1", status: "revoked", save: async function () {} },
      ],
    },
    async ({ controller }) => {
      const res = makeRes();
      await controller.acceptCaregiverGrant(
        { params: { id: "g1" }, user_id: "cg_1" },
        res
      );
      assert.strictEqual(res.statusCode, 409);
    }
  );
});

test("revoke endpoint: owner revokes an accepted grant -> access cut (device.caregiver_id cleared)", async () => {
  await withStubbedController(
    {
      devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: "cg_1", isActive: true, save: async function () {} }],
      users: [{ user_id: "cg_1", caregiving_device_ids: ["D1"], save: async function () {} }],
      grants: [
        { _id: "g1", deviceId: "D1", patientUserId: "owner_1", caregiverUserId: "cg_1", status: "accepted", save: async function () {} },
      ],
    },
    async ({ controller, devices }) => {
      const res = makeRes();
      await controller.revokeCaregiverGrant(
        { params: { id: "g1" }, user_id: "owner_1" },
        res
      );
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.body.grant.status, "revoked");
      assert.strictEqual(devices[0].caregiver_id, null);
    }
  );
});

test("revoke endpoint: caregiver may revoke (decline) their own pending invite", async () => {
  await withStubbedController(
    {
      devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: null, isActive: true, save: async function () {} }],
      grants: [
        { _id: "g1", deviceId: "D1", patientUserId: "owner_1", caregiverUserId: "cg_1", status: "pending", save: async function () {} },
      ],
    },
    async ({ controller }) => {
      const res = makeRes();
      await controller.revokeCaregiverGrant(
        { params: { id: "g1" }, user_id: "cg_1" },
        res
      );
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.body.grant.status, "revoked");
    }
  );
});

test("revoke endpoint: an unrelated user cannot revoke (403)", async () => {
  await withStubbedController(
    {
      devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: "cg_1", isActive: true, save: async function () {} }],
      grants: [
        { _id: "g1", deviceId: "D1", patientUserId: "owner_1", caregiverUserId: "cg_1", status: "accepted", save: async function () {} },
      ],
    },
    async ({ controller }) => {
      const res = makeRes();
      await controller.revokeCaregiverGrant(
        { params: { id: "g1" }, user_id: "attacker" },
        res
      );
      assert.strictEqual(res.statusCode, 403);
    }
  );
});

test("state machine: revoking an already-revoked grant is rejected (409)", async () => {
  await withStubbedController(
    {
      devices: [{ device_id: "D1", user_id: "owner_1", caregiver_id: null, isActive: true }],
      grants: [
        { _id: "g1", deviceId: "D1", patientUserId: "owner_1", caregiverUserId: "cg_1", status: "revoked", save: async function () {} },
      ],
    },
    async ({ controller }) => {
      const res = makeRes();
      await controller.revokeCaregiverGrant(
        { params: { id: "g1" }, user_id: "owner_1" },
        res
      );
      assert.strictEqual(res.statusCode, 409);
    }
  );
});

// ============================================
// GTM-517 — list-grants endpoint (server-authoritative, PHI-free)
// ============================================

const LIST_SEED = {
  grants: [
    // me (u_me) as caregiver: one pending invite, one accepted relationship.
    { _id: "lg1", deviceId: "D1", patientUserId: "owner_1", caregiverUserId: "u_me", status: "pending" },
    { _id: "lg2", deviceId: "D2", patientUserId: "owner_2", caregiverUserId: "u_me", status: "accepted" },
    // me (u_me) as owner/patient: a caregiver I invited (accepted).
    { _id: "lg3", deviceId: "D3", patientUserId: "u_me", caregiverUserId: "cg_x", status: "accepted" },
    // unrelated grant that must NEVER appear for u_me.
    { _id: "lg4", deviceId: "D9", patientUserId: "owner_9", caregiverUserId: "cg_other", status: "pending" },
  ],
};

test("list grants: returns both buckets keyed off the SESSION user id only", async () => {
  await withStubbedController(LIST_SEED, async ({ controller }) => {
    const res = makeRes();
    await controller.listCaregiverGrants({ user_id: "u_me", query: {} }, res);
    assert.strictEqual(res.statusCode, 200);

    const cgIds = res.body.as_caregiver.map((g) => g.id).sort();
    const ownerIds = res.body.as_owner.map((g) => g.id).sort();
    assert.deepStrictEqual(cgIds, ["lg1", "lg2"]);
    assert.deepStrictEqual(ownerIds, ["lg3"]);
    // The unrelated grant lg4 appears in neither bucket.
    assert.ok(![...cgIds, ...ownerIds].includes("lg4"));
  });
});

test("list grants: a client-supplied userId in the query is ignored (session id wins)", async () => {
  await withStubbedController(LIST_SEED, async ({ controller }) => {
    const res = makeRes();
    // Attacker tries to read cg_other's grants by spoofing the query — must fail.
    await controller.listCaregiverGrants(
      { user_id: "u_me", query: { userId: "cg_other", caregiverUserId: "cg_other" } },
      res
    );
    assert.strictEqual(res.statusCode, 200);
    const all = [...res.body.as_caregiver, ...res.body.as_owner].map((g) => g.id);
    assert.ok(!all.includes("lg4"));
  });
});

test("list grants: ?status=pending returns only pending grants (e.g. the invites inbox)", async () => {
  await withStubbedController(LIST_SEED, async ({ controller }) => {
    const res = makeRes();
    await controller.listCaregiverGrants(
      { user_id: "u_me", query: { status: "pending" } },
      res
    );
    assert.strictEqual(res.statusCode, 200);
    assert.deepStrictEqual(res.body.as_caregiver.map((g) => g.id), ["lg1"]);
    assert.strictEqual(res.body.as_owner.length, 0);
  });
});

test("list grants: ?role=caregiver returns only the caregiver bucket", async () => {
  await withStubbedController(LIST_SEED, async ({ controller }) => {
    const res = makeRes();
    await controller.listCaregiverGrants(
      { user_id: "u_me", query: { role: "caregiver" } },
      res
    );
    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.body.as_caregiver.length, 2);
    assert.strictEqual(res.body.as_owner.length, 0);
  });
});

test("list grants: PHI-free shape — only ids/status/timestamps, no device telemetry", async () => {
  await withStubbedController(LIST_SEED, async ({ controller }) => {
    const res = makeRes();
    await controller.listCaregiverGrants({ user_id: "u_me", query: {} }, res);
    const sample = res.body.as_caregiver[0];
    // Allowed keys only — no recent_events / battery / patient name etc.
    const allowed = new Set([
      "id", "device_id", "patient_user_id", "caregiver_user_id", "status",
      "invited_at", "invited_by", "accepted_at", "accepted_by",
      "revoked_at", "revoked_by",
    ]);
    for (const k of Object.keys(sample)) {
      assert.ok(allowed.has(k), `unexpected PHI-bearing key in grant: ${k}`);
    }
  });
});

test("list grants: an invalid ?status filter is rejected (400)", async () => {
  await withStubbedController(LIST_SEED, async ({ controller }) => {
    const res = makeRes();
    await controller.listCaregiverGrants(
      { user_id: "u_me", query: { status: "bogus" } },
      res
    );
    assert.strictEqual(res.statusCode, 400);
  });
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
