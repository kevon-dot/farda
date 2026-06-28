const test = require("node:test");
const assert = require("node:assert");
const Module = require("module");

// ============================================
// GTM-519 — Dose-event microstructure endpoint tests
// ============================================
// Controller-level tests with the Mongoose models stubbed via the require cache,
// so no live MongoDB is needed (matches tests/userIngestRelay.test.js style).
// These prove the capture endpoint is deny-by-default authenticated (via the
// shared verifyUserToken guard, asserted at the end), IDOR-guarded (device must
// be OWNED by the session user), server-authoritative (server stamps recordedAt
// + assigns stage order), audited PHI-free, and rejects malformed sequences.

const { DOSE_STAGE } = require("../utils/doseEventValidation");

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

function fullStages() {
  return [
    { type: DOSE_STAGE.REMINDER_FIRED, timestamp: 1000, payload: { reminder_index: 0, channel: "PUSH" } },
    { type: DOSE_STAGE.REMINDER_OPENED, timestamp: 1005, payload: { time_to_action_ms: 5000 } },
    { type: DOSE_STAGE.UNLOCK, timestamp: 1010 },
    { type: DOSE_STAGE.CAP_OPEN, timestamp: 1011, payload: { duration_ms: 1200 } },
    { type: DOSE_STAGE.WEIGH_BEFORE, timestamp: 1012, payload: { weight_mg: 5000 } },
    { type: DOSE_STAGE.WEIGH_AFTER, timestamp: 1013, payload: { weight_mg: 4750 } },
    { type: DOSE_STAGE.WEIGHT_DELTA, timestamp: 1014, payload: { delta_mg: -250 } },
    { type: DOSE_STAGE.CAP_CLOSE, timestamp: 1015, payload: { duration_ms: 800 } },
    { type: DOSE_STAGE.SYNC, timestamp: 1020, payload: { transport: "BLE" } },
  ];
}

const validBody = (overrides = {}) => ({
  client_dose_id: "dose-uuid-1",
  idempotency_key: "idem_abc123",
  stages: fullStages(),
  ...overrides,
});

// Load app.api.controller with Device/Event/User/CaregiverGrant/DoseEvent stubbed.
function withStubbedController(seed, run) {
  const devicePath = require.resolve("../models/Device");
  const eventPath = require.resolve("../models/Event");
  const userPath = require.resolve("../models/User");
  const grantPath = require.resolve("../models/CaregiverGrant");
  const doseEventPath = require.resolve("../models/DoseEvent");
  const ctrlPath = require.resolve("../controllers/app.api.controller");

  const paths = [devicePath, eventPath, userPath, grantPath, doseEventPath, ctrlPath];
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
  const existing = (seed.doseEvents || []).slice();
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
  // The relay's Event model is not exercised here; stub it inert.
  stub(eventPath, { findOne: async () => null });
  stub(userPath, { findOne: async () => null });
  stub(grantPath, { updateMany: async () => ({}) });

  class StubDoseEvent {
    constructor(doc) {
      Object.assign(this, doc);
      this._id = `dose_${created.length + 1}`;
    }
    async save() {
      if (this.idempotency_key) {
        const dup =
          existing.some((e) => e.idempotency_key === this.idempotency_key) ||
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
      const all = existing.concat(created);
      return all.find((e) => e.idempotency_key === q.idempotency_key) || null;
    }
  }
  stub(doseEventPath, StubDoseEvent);

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

// ----------------------------------------------------------------------------

test("owner captures a valid microstructure: 201, DoseEvent created, server-ordered, last_sync stamped", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }] },
    async ({ controller, devices, created }) => {
      const res = makeRes();
      await controller.ingestDoseEventMicrostructure(
        { params: { device_id: "D1" }, user_id: "owner_1", body: validBody() },
        res
      );
      assert.strictEqual(res.statusCode, 201);
      assert.strictEqual(res.body.deduped, false);
      assert.strictEqual(created.length, 1);
      // Subject bound from session/device, never client body.
      assert.strictEqual(created[0].device_id, "D1");
      assert.strictEqual(created[0].user_id, "owner_1");
      // Server stamped the canonical record time + contiguous order.
      assert.ok(created[0].recordedAt instanceof Date);
      assert.deepStrictEqual(
        created[0].stages.map((s) => s.order),
        [0, 1, 2, 3, 4, 5, 6, 7, 8]
      );
      // Tokenization-ready sequence echoed back.
      assert.strictEqual(res.body.dose_event.token_sequence[0], "REMINDER_FIRED@0");
      // last_sync_at stamped (GTM-539 registry field).
      assert.ok(devices[0].last_sync_at instanceof Date);
    }
  );
});

test("server reorders client-shuffled stages (client ordering not trusted)", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }] },
    async ({ controller, created }) => {
      const s = fullStages();
      const shuffled = [s[8], s[0], s[4], s[2], s[6], s[1], s[3], s[5], s[7]];
      const res = makeRes();
      await controller.ingestDoseEventMicrostructure(
        { params: { device_id: "D1" }, user_id: "owner_1", body: validBody({ stages: shuffled }) },
        res
      );
      assert.strictEqual(res.statusCode, 201);
      assert.strictEqual(created[0].stages[0].type, DOSE_STAGE.REMINDER_FIRED);
      assert.strictEqual(created[0].stages.at(-1).type, DOSE_STAGE.SYNC);
    }
  );
});

test("IDOR: non-owner is forbidden (403), no DoseEvent", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }] },
    async ({ controller, created }) => {
      const res = makeRes();
      await controller.ingestDoseEventMicrostructure(
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
    await controller.ingestDoseEventMicrostructure(
      { params: { device_id: "NOPE" }, user_id: "owner_1", body: validBody() },
      res
    );
    assert.strictEqual(res.statusCode, 404);
    assert.strictEqual(created.length, 0);
  });
});

test("malformed: out-of-order sequence is rejected 400, no DoseEvent", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }] },
    async ({ controller, created }) => {
      const s = fullStages();
      s.find((x) => x.type === DOSE_STAGE.UNLOCK).timestamp = 1011;
      s.find((x) => x.type === DOSE_STAGE.CAP_OPEN).timestamp = 1010;
      const res = makeRes();
      await controller.ingestDoseEventMicrostructure(
        { params: { device_id: "D1" }, user_id: "owner_1", body: validBody({ stages: s }) },
        res
      );
      assert.strictEqual(res.statusCode, 400);
      assert.strictEqual(created.length, 0);
    }
  );
});

test("malformed: missing required stage is rejected 400", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }] },
    async ({ controller, created }) => {
      const s = fullStages().filter((x) => x.type !== DOSE_STAGE.SYNC);
      const res = makeRes();
      await controller.ingestDoseEventMicrostructure(
        { params: { device_id: "D1" }, user_id: "owner_1", body: validBody({ stages: s }) },
        res
      );
      assert.strictEqual(res.statusCode, 400);
      assert.strictEqual(created.length, 0);
    }
  );
});

test("PHI smuggled in a stage payload is rejected 400 (no DoseEvent written)", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }] },
    async ({ controller, created }) => {
      const s = fullStages();
      s.find((x) => x.type === DOSE_STAGE.WEIGH_AFTER).payload = {
        weight_mg: 4750,
        patient_note: "John Doe Lisinopril",
      };
      const res = makeRes();
      await controller.ingestDoseEventMicrostructure(
        { params: { device_id: "D1" }, user_id: "owner_1", body: validBody({ stages: s }) },
        res
      );
      assert.strictEqual(res.statusCode, 400);
      assert.strictEqual(created.length, 0);
    }
  );
});

test("idempotent on retry: same key twice creates exactly one DoseEvent", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }] },
    async ({ controller, created }) => {
      const req = { params: { device_id: "D1" }, user_id: "owner_1", body: validBody() };

      const res1 = makeRes();
      await controller.ingestDoseEventMicrostructure(req, res1);
      assert.strictEqual(res1.statusCode, 201);
      assert.strictEqual(res1.body.deduped, false);

      const res2 = makeRes();
      await controller.ingestDoseEventMicrostructure(req, res2);
      assert.strictEqual(res2.statusCode, 200);
      assert.strictEqual(res2.body.deduped, true);

      assert.strictEqual(created.length, 1);
    }
  );
});

test("a client-supplied user id in the body is ignored; session user_id is bound", async () => {
  await withStubbedController(
    { devices: [{ device_id: "D1", user_id: "owner_1", claimed: true }] },
    async ({ controller, created }) => {
      const res = makeRes();
      await controller.ingestDoseEventMicrostructure(
        {
          params: { device_id: "D1" },
          user_id: "owner_1",
          body: validBody({ user_id: "attacker", device_id: "OTHER" }),
        },
        res
      );
      assert.strictEqual(res.statusCode, 201);
      assert.strictEqual(created.length, 1);
      assert.strictEqual(created[0].user_id, "owner_1");
      assert.strictEqual(created[0].device_id, "D1");
    }
  );
});

// ============================================
// Auth required: verifyUserToken guards the route (deny-by-default)
// ============================================
test("missing session: verifyUserToken returns 401 before the capture runs", async () => {
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

  stub(authPath, { betterAuth: () => ({ api: { getSession: async () => null } }) });
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
