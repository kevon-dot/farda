const test = require("node:test");
const assert = require("node:assert");
const Module = require("module");

// ============================================
// GTM-521 — Ground-truth endpoint tests
// ============================================
// Controller-level tests with the Mongoose models stubbed via the require cache
// (no live MongoDB), matching tests/doseEventMicrostructure.test.js style. These
// prove the EMA + pill-count record endpoints and the sens/spec read endpoint are
// IDOR-guarded (device must be OWNED by the session user), subject-bound
// server-side (client ids ignored), idempotent, and that the read endpoint
// returns the correct sensitivity/specificity from EMA labels vs detected
// DoseEvents. Route auth (verifyUserToken) is covered in
// tests/doseEventMicrostructure.test.js (same shared guard on the same router).

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

// Load app.api.controller with all models stubbed against in-memory seed data.
function withStubbedController(seed, run) {
  const devicePath = require.resolve("../models/Device");
  const eventPath = require.resolve("../models/Event");
  const userPath = require.resolve("../models/User");
  const grantPath = require.resolve("../models/CaregiverGrant");
  const doseEventPath = require.resolve("../models/DoseEvent");
  const emaPath = require.resolve("../models/EmaResponse");
  const pillPath = require.resolve("../models/PillCountCheckpoint");
  const ctrlPath = require.resolve("../controllers/app.api.controller");

  const paths = [
    devicePath, eventPath, userPath, grantPath, doseEventPath,
    emaPath, pillPath, ctrlPath,
  ];
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
  const seededDose = (seed.doseEvents || []).slice();
  const seededEma = (seed.emaResponses || []).slice();
  const createdEma = [];
  const createdPill = [];

  function stub(path, exports) {
    const m = new Module(path, module);
    m.exports = exports;
    m.loaded = true;
    require.cache[path] = m;
  }

  stub(devicePath, {
    findOne: async (q) => devices.find((d) => d.device_id === q.device_id) || null,
  });
  stub(eventPath, { findOne: async () => null });
  stub(userPath, { findOne: async () => null });
  stub(grantPath, { updateMany: async () => ({}) });

  // DoseEvent: support findOne(idempotency_key) + find(query) for the read path.
  // The read controller does `await DoseEvent.find(...)` (no .sort), so return the
  // array directly (await on an array resolves to itself).
  stub(doseEventPath, {
    findOne: async () => null,
    find: async (q) =>
      seededDose.filter(
        (d) =>
          (!q.user_id || d.user_id === q.user_id) &&
          (!q.device_id || d.device_id === q.device_id)
      ),
  });

  // Helper to build a Model-like stub with new()/save()/findOne()/find().
  function makeModelStub(seededRows, createdRows) {
    return class StubModel {
      constructor(doc) {
        Object.assign(this, doc);
        this._id = `m_${createdRows.length + 1}`;
        if (typeof this.discrepancy === "undefined" &&
            typeof this.manual_count === "number" &&
            typeof this.device_inferred_count === "number") {
          this.discrepancy = this.manual_count - this.device_inferred_count;
        }
      }
      async save() {
        if (this.idempotency_key) {
          const dup =
            seededRows.some((e) => e.idempotency_key === this.idempotency_key) ||
            createdRows.some((e) => e.idempotency_key === this.idempotency_key);
          if (dup) {
            const err = new Error("E11000 duplicate key");
            err.code = 11000;
            throw err;
          }
        }
        createdRows.push(this);
        return this;
      }
      static async findOne(q) {
        const all = seededRows.concat(createdRows);
        return all.find((e) => e.idempotency_key === q.idempotency_key) || null;
      }
      static find(q) {
        const rows = seededRows
          .concat(createdRows)
          .filter(
            (e) =>
              (!q.user_id || e.user_id === q.user_id) &&
              (!q.device_id || e.device_id === q.device_id)
          );
        return { sort: () => rows };
      }
    };
  }

  stub(emaPath, makeModelStub(seededEma, createdEma));
  stub(pillPath, makeModelStub([], createdPill));

  delete require.cache[ctrlPath];
  const controller = require(ctrlPath);

  return Promise.resolve(
    run({ controller, devices, createdEma, createdPill })
  ).finally(() => {
    for (const p of paths) {
      if (saved[p]) require.cache[p] = saved[p];
      else delete require.cache[p];
    }
    delete require.cache[ctrlPath];
  });
}

const OWNED = { device_id: "D1", user_id: "owner_1", claimed: true };

// ============================================
// EMA record endpoint
// ============================================

test("EMA record: owner posts a valid self-report ⇒ 201, row created, subject bound", async () => {
  await withStubbedController({ devices: [{ ...OWNED }] }, async ({ controller, createdEma }) => {
    const res = makeRes();
    await controller.recordEmaResponse(
      {
        params: { device_id: "D1" },
        user_id: "owner_1",
        body: { self_reported_taken: "yes", dose_event_id: "dose_42", idempotency_key: "ema_1" },
      },
      res
    );
    assert.strictEqual(res.statusCode, 201);
    assert.strictEqual(res.body.deduped, false);
    assert.strictEqual(createdEma.length, 1);
    assert.strictEqual(createdEma[0].user_id, "owner_1"); // session-bound
    assert.strictEqual(createdEma[0].device_id, "D1"); // path-bound
    assert.strictEqual(createdEma[0].self_reported_taken, "taken"); // normalized
    assert.strictEqual(createdEma[0].dose_event_id, "dose_42");
  });
});

test("EMA record: invalid answer ⇒ 400, no row", async () => {
  await withStubbedController({ devices: [{ ...OWNED }] }, async ({ controller, createdEma }) => {
    const res = makeRes();
    await controller.recordEmaResponse(
      { params: { device_id: "D1" }, user_id: "owner_1", body: { self_reported_taken: "banana" } },
      res
    );
    assert.strictEqual(res.statusCode, 400);
    assert.strictEqual(createdEma.length, 0);
  });
});

test("EMA record: IDOR — non-owner ⇒ 403, no row", async () => {
  await withStubbedController({ devices: [{ ...OWNED }] }, async ({ controller, createdEma }) => {
    const res = makeRes();
    await controller.recordEmaResponse(
      { params: { device_id: "D1" }, user_id: "attacker", body: { self_reported_taken: "yes" } },
      res
    );
    assert.strictEqual(res.statusCode, 403);
    assert.strictEqual(createdEma.length, 0);
  });
});

test("EMA record: unknown device ⇒ 404", async () => {
  await withStubbedController({ devices: [] }, async ({ controller, createdEma }) => {
    const res = makeRes();
    await controller.recordEmaResponse(
      { params: { device_id: "NOPE" }, user_id: "owner_1", body: { self_reported_taken: "no" } },
      res
    );
    assert.strictEqual(res.statusCode, 404);
    assert.strictEqual(createdEma.length, 0);
  });
});

test("EMA record: client-supplied user_id/device_id in body are ignored", async () => {
  await withStubbedController({ devices: [{ ...OWNED }] }, async ({ controller, createdEma }) => {
    const res = makeRes();
    await controller.recordEmaResponse(
      {
        params: { device_id: "D1" },
        user_id: "owner_1",
        body: { self_reported_taken: "yes", user_id: "attacker", device_id: "OTHER" },
      },
      res
    );
    assert.strictEqual(res.statusCode, 201);
    assert.strictEqual(createdEma[0].user_id, "owner_1");
    assert.strictEqual(createdEma[0].device_id, "D1");
  });
});

test("EMA record: idempotent on retry — same key twice ⇒ exactly one row", async () => {
  await withStubbedController({ devices: [{ ...OWNED }] }, async ({ controller, createdEma }) => {
    const req = {
      params: { device_id: "D1" },
      user_id: "owner_1",
      body: { self_reported_taken: "yes", idempotency_key: "ema_dup" },
    };
    const r1 = makeRes();
    await controller.recordEmaResponse(req, r1);
    assert.strictEqual(r1.statusCode, 201);
    const r2 = makeRes();
    await controller.recordEmaResponse(req, r2);
    assert.strictEqual(r2.statusCode, 200);
    assert.strictEqual(r2.body.deduped, true);
    assert.strictEqual(createdEma.length, 1);
  });
});

// ============================================
// Pill-count checkpoint endpoint
// ============================================

test("pill-count record: owner posts counts ⇒ 201, discrepancy server-computed", async () => {
  await withStubbedController({ devices: [{ ...OWNED }] }, async ({ controller, createdPill }) => {
    const res = makeRes();
    await controller.recordPillCountCheckpoint(
      {
        params: { device_id: "D1" },
        user_id: "owner_1",
        body: { manual_count: 14, device_inferred_count: 12, idempotency_key: "pc_1" },
      },
      res
    );
    assert.strictEqual(res.statusCode, 201);
    assert.strictEqual(createdPill.length, 1);
    assert.strictEqual(createdPill[0].user_id, "owner_1");
    assert.strictEqual(createdPill[0].discrepancy, 2); // 14 - 12
    assert.strictEqual(res.body.checkpoint.discrepancy, 2);
  });
});

test("pill-count record: negative / non-integer counts ⇒ 400", async () => {
  await withStubbedController({ devices: [{ ...OWNED }] }, async ({ controller, createdPill }) => {
    const res = makeRes();
    await controller.recordPillCountCheckpoint(
      { params: { device_id: "D1" }, user_id: "owner_1", body: { manual_count: -1, device_inferred_count: 5 } },
      res
    );
    assert.strictEqual(res.statusCode, 400);
    assert.strictEqual(createdPill.length, 0);
  });
});

test("pill-count record: IDOR — non-owner ⇒ 403", async () => {
  await withStubbedController({ devices: [{ ...OWNED }] }, async ({ controller, createdPill }) => {
    const res = makeRes();
    await controller.recordPillCountCheckpoint(
      { params: { device_id: "D1" }, user_id: "attacker", body: { manual_count: 5, device_inferred_count: 5 } },
      res
    );
    assert.strictEqual(res.statusCode, 403);
    assert.strictEqual(createdPill.length, 0);
  });
});

test("pill-count record: idempotent on retry ⇒ exactly one row", async () => {
  await withStubbedController({ devices: [{ ...OWNED }] }, async ({ controller, createdPill }) => {
    const req = {
      params: { device_id: "D1" },
      user_id: "owner_1",
      body: { manual_count: 10, device_inferred_count: 10, idempotency_key: "pc_dup" },
    };
    const r1 = makeRes();
    await controller.recordPillCountCheckpoint(req, r1);
    assert.strictEqual(r1.statusCode, 201);
    const r2 = makeRes();
    await controller.recordPillCountCheckpoint(req, r2);
    assert.strictEqual(r2.statusCode, 200);
    assert.strictEqual(r2.body.deduped, true);
    assert.strictEqual(createdPill.length, 1);
  });
});

// ============================================
// Sens/spec read endpoint
// ============================================

test("metrics read: pairs EMA labels to detected DoseEvents via dose_event_id ⇒ correct sens/spec", async () => {
  // Two detected doses (linked to two 'taken' EMAs ⇒ TP). One 'taken' EMA with no
  // detection ⇒ FN. One 'not_taken' EMA with no detection ⇒ TN.
  //   TP=2, FN=1, TN=1, FP=0 ⇒ sensitivity = 2/3 = 0.6667, specificity = 1/1 = 1.
  const now = Date.now();
  await withStubbedController(
    {
      devices: [{ ...OWNED }],
      doseEvents: [
        { _id: "dose_1", user_id: "owner_1", device_id: "D1", recordedAt: new Date(now) },
        { _id: "dose_2", user_id: "owner_1", device_id: "D1", recordedAt: new Date(now) },
      ],
      emaResponses: [
        { user_id: "owner_1", device_id: "D1", dose_event_id: "dose_1", self_reported_taken: "taken", responded_at: new Date(now) },
        { user_id: "owner_1", device_id: "D1", dose_event_id: "dose_2", self_reported_taken: "taken", responded_at: new Date(now) },
        { user_id: "owner_1", device_id: "D1", dose_event_id: null, self_reported_taken: "taken", responded_at: new Date(now + 5 * 60 * 60 * 1000) },
        { user_id: "owner_1", device_id: "D1", dose_event_id: null, self_reported_taken: "not_taken", responded_at: new Date(now + 6 * 60 * 60 * 1000) },
      ],
    },
    async ({ controller }) => {
      const res = makeRes();
      await controller.getDoseDetectionMetrics(
        { params: { device_id: "D1" }, user_id: "owner_1", query: {} },
        res
      );
      assert.strictEqual(res.statusCode, 200);
      const m = res.body.metrics;
      assert.deepStrictEqual(m.counts, { tp: 2, fp: 0, fn: 1, tn: 1 });
      assert.strictEqual(m.sensitivity, 0.6667);
      assert.strictEqual(m.specificity, 1);
      assert.strictEqual(m.sampleSize, 4);
    }
  );
});

test("metrics read: no labels ⇒ 200 with null (undefined) rates", async () => {
  await withStubbedController({ devices: [{ ...OWNED }] }, async ({ controller }) => {
    const res = makeRes();
    await controller.getDoseDetectionMetrics(
      { params: { device_id: "D1" }, user_id: "owner_1", query: {} },
      res
    );
    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.body.metrics.sensitivity, null);
    assert.strictEqual(res.body.metrics.sampleSize, 0);
  });
});

test("metrics read: IDOR — non-owner ⇒ 403", async () => {
  await withStubbedController({ devices: [{ ...OWNED }] }, async ({ controller }) => {
    const res = makeRes();
    await controller.getDoseDetectionMetrics(
      { params: { device_id: "D1" }, user_id: "attacker", query: {} },
      res
    );
    assert.strictEqual(res.statusCode, 403);
  });
});
