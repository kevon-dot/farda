const test = require("node:test");
const assert = require("node:assert");
const Module = require("module");

// ============================================
// GTM-514 — user-bearer dose-event ingest relay
// ============================================
// Controller-level tests with the Mongoose models stubbed via the require cache,
// so no live MongoDB is needed (matches tests/caregiverController.test.js style).
// These prove the relay is server-authoritative: the acting user is the session
// user (req.user_id), the device must be OWNED by that user, malformed events are
// rejected, and the client-computed idempotency_key dedupes.

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

// Load app.api.controller with Device/Event/User/CaregiverGrant stubbed.
// `seed` provides in-memory fixtures; `created` collects saved Events so tests
// can assert exactly one (or zero) row was written.
function withStubbedController(seed, run) {
  const devicePath = require.resolve("../models/Device");
  const eventPath = require.resolve("../models/Event");
  const userPath = require.resolve("../models/User");
  const grantPath = require.resolve("../models/CaregiverGrant");
  const ctrlPath = require.resolve("../controllers/app.api.controller");

  const paths = [devicePath, eventPath, userPath, grantPath, ctrlPath];
  const saved = {};
  for (const p of paths) saved[p] = require.cache[p];

  const devices = (seed.devices || []).map((d) => ({
    last_seen: null,
    last_sync_at: null,
    save: async function () {
      return this;
    },
    ...d,
  }));
  // In-memory Event store keyed by idempotency_key (only non-null keys indexed).
  const existingEvents = (seed.events || []).slice();
  const created = [];

  function stub(path, exports) {
    const m = new Module(path, module);
    m.exports = exports;
    m.loaded = true;
    require.cache[path] = m;
  }

  stub(devicePath, {
    findOne: async (q) => devices.find((d) => d.device_id === q.device_id) || null,
  });

  class StubEvent {
    constructor(doc) {
      Object.assign(this, doc);
    }
    async save() {
      // Enforce the unique idempotency_key index for non-null keys.
      if (this.idempotency_key) {
        const dup =
          existingEvents.some((e) => e.idempotency_key === this.idempotency_key) ||
          created.some((e) => e.idempotency_key === this.idempotency_key);
        if (dup) {
          const err = new Error("E11000 duplicate key");
          err.code = 11000;
          throw err;
        }
      }
      created.push(this);
      return this;
    }
    static async findOne(q) {
      const all = existingEvents.concat(created);
      return all.find((e) => e.idempotency_key === q.idempotency_key) || null;
    }
  }
  stub(eventPath, StubEvent);
  stub(userPath, { findOne: async () => null });
  stub(grantPath, { updateMany: async () => ({}) });

  delete require.cache[ctrlPath];
  const controller = require(ctrlPath);

  return Promise.resolve(run({ controller, devices, created })).finally(() => {
    for (const p of paths) {
      if (saved[p]) require.cache[p] = saved[p];
      else delete require.cache[p];
    }
    delete require.cache[ctrlPath];
  });
}

const validBody = (overrides = {}) => ({
  device_id: "D1",
  event: "OPEN",
  timestamp: 1738483200,
  sequence: 3,
  idempotency_key: "idem_abc",
  payload: { duration: 2 },
  ...overrides,
});

// ----------------------------------------------------------------------------

test("owner can ingest a valid event: 200, Event created, last_sync stamped", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }] },
    async ({ controller, devices, created }) => {
      const res = makeRes();
      await controller.ingestUserDeviceEvent(
        { params: { device_id: "D1" }, user_id: "owner_1", body: validBody() },
        res
      );
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.body.deduped, false);
      assert.strictEqual(created.length, 1);
      assert.strictEqual(created[0].device_id, "D1");
      assert.strictEqual(created[0].event_type, "OPEN");
      assert.strictEqual(created[0].idempotency_key, "idem_abc");
      assert.strictEqual(created[0].sequence, 3);
      // last_sync_at stamped (GTM-539 registry field).
      assert.ok(devices[0].last_sync_at instanceof Date);
    }
  );
});

test("non-owner (device claimed by someone else) is forbidden: 403, no Event", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }] },
    async ({ controller, created }) => {
      const res = makeRes();
      await controller.ingestUserDeviceEvent(
        { params: { device_id: "D1" }, user_id: "attacker", body: validBody() },
        res
      );
      assert.strictEqual(res.statusCode, 403);
      assert.strictEqual(created.length, 0);
    }
  );
});

test("unknown device is 404", async () => {
  await withStubbedController({ devices: [] }, async ({ controller, created }) => {
    const res = makeRes();
    await controller.ingestUserDeviceEvent(
      { params: { device_id: "NOPE" }, user_id: "owner_1", body: validBody({ device_id: "NOPE" }) },
      res
    );
    assert.strictEqual(res.statusCode, 404);
    assert.strictEqual(created.length, 0);
  });
});

test("malformed event (unknown event_type) is rejected: 400, no Event", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }] },
    async ({ controller, created }) => {
      const res = makeRes();
      await controller.ingestUserDeviceEvent(
        { params: { device_id: "D1" }, user_id: "owner_1", body: validBody({ event: "NOT_A_REAL_EVENT" }) },
        res
      );
      assert.strictEqual(res.statusCode, 400);
      assert.strictEqual(created.length, 0);
    }
  );
});

test("malformed event (bad payload shape) is rejected: 400", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }] },
    async ({ controller, created }) => {
      const res = makeRes();
      await controller.ingestUserDeviceEvent(
        {
          params: { device_id: "D1" },
          user_id: "owner_1",
          // OPEN.duration must be a non-negative number.
          body: validBody({ payload: { duration: -5 } }),
        },
        res
      );
      assert.strictEqual(res.statusCode, 400);
      assert.strictEqual(created.length, 0);
    }
  );
});

test("duplicate idempotency_key returns 200 deduped with no second create (pre-existing)", async () => {
  await withStubbedController(
    {
      devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }],
      events: [{ idempotency_key: "idem_abc", device_id: "D1", event_type: "OPEN" }],
    },
    async ({ controller, created }) => {
      const res = makeRes();
      await controller.ingestUserDeviceEvent(
        { params: { device_id: "D1" }, user_id: "owner_1", body: validBody() },
        res
      );
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(res.body.deduped, true);
      assert.strictEqual(created.length, 0);
    }
  );
});

test("idempotent on retry: same key posted twice creates exactly one Event", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }] },
    async ({ controller, created }) => {
      const req = { params: { device_id: "D1" }, user_id: "owner_1", body: validBody() };

      const res1 = makeRes();
      await controller.ingestUserDeviceEvent(req, res1);
      assert.strictEqual(res1.statusCode, 200);
      assert.strictEqual(res1.body.deduped, false);

      const res2 = makeRes();
      await controller.ingestUserDeviceEvent(req, res2);
      assert.strictEqual(res2.statusCode, 200);
      assert.strictEqual(res2.body.deduped, true);

      assert.strictEqual(created.length, 1);
    }
  );
});

test("a client-supplied user id in the body is ignored; session user_id decides ownership", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }] },
    async ({ controller, created }) => {
      const res = makeRes();
      await controller.ingestUserDeviceEvent(
        {
          params: { device_id: "D1" },
          user_id: "owner_1",
          // Attacker tries to spoof a different acting user via the body.
          body: validBody({ user_id: "attacker" }),
        },
        res
      );
      assert.strictEqual(res.statusCode, 200);
      assert.strictEqual(created.length, 1);
    }
  );
});

// ============================================
// Missing session -> 401 (verifyUserToken guards the route)
// ============================================
// The relay is mounted under the user router behind verifyUserToken; a request
// with no valid better-auth session never reaches the controller. We assert the
// middleware returns 401 (matches deviceAuth/verifyAdmin pure-middleware tests).

test("missing session: verifyUserToken returns 401 before the relay runs", async () => {
  const authPath = require.resolve("better-auth");
  const nodePath = require.resolve("better-auth/node");
  const mwPath = require.resolve("../middleware/verifyUserToken");
  const saved = {
    [authPath]: require.cache[authPath],
    [nodePath]: require.cache[nodePath],
    [mwPath]: require.cache[mwPath],
  };

  function stub(path, exports) {
    const m = new Module(path, module);
    m.exports = exports;
    m.loaded = true;
    require.cache[path] = m;
  }

  // better-auth returns no session -> middleware must 401.
  stub(authPath, {
    betterAuth: () => ({ api: { getSession: async () => null } }),
  });
  stub(nodePath, { fromNodeHeaders: () => ({}) });

  delete require.cache[mwPath];
  const verifyToken = require(mwPath);

  try {
    const res = makeRes();
    let nextCalled = false;
    await verifyToken({ headers: {} }, res, () => {
      nextCalled = true;
    });
    assert.strictEqual(res.statusCode, 401);
    assert.strictEqual(nextCalled, false);
  } finally {
    for (const [p, m] of Object.entries(saved)) {
      if (m) require.cache[p] = m;
      else delete require.cache[p];
    }
    delete require.cache[mwPath];
  }
});
