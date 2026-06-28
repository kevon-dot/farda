const test = require("node:test");
const assert = require("node:assert");

// ============================================
// GTM-519 — Dose-event microstructure schema / validation unit tests
// ============================================
// Pure validator tests (no DB, no models). Prove the microstructure is typed,
// ordered, complete, server-authoritative, tokenization-ready, and PHI-free.

const {
  SCHEMA_VERSION,
  DOSE_STAGE,
  validateDoseEventMicrostructure,
} = require("../utils/doseEventValidation");

// A complete, well-formed dose lifecycle. Reminder microbehaviors precede the
// mandatory interaction backbone. Timestamps are monotonically increasing.
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

function validBody(overrides = {}) {
  return {
    client_dose_id: "dose-uuid-1",
    idempotency_key: "idem_abc123",
    stages: fullStages(),
    ...overrides,
  };
}

// ----------------------------------------------------------------------------
// Well-formed acceptance
// ----------------------------------------------------------------------------

test("well-formed full lifecycle is accepted", () => {
  const r = validateDoseEventMicrostructure(validBody());
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.value.schema_version, SCHEMA_VERSION);
  assert.strictEqual(r.value.stages.length, 9);
});

test("server assigns a contiguous 0..N-1 order regardless of client array order", () => {
  // Shuffle the wire order; the server must re-order by device timestamp.
  const stages = fullStages();
  const shuffled = [stages[8], stages[2], stages[0], stages[5], stages[1], stages[3], stages[6], stages[4], stages[7]];
  const r = validateDoseEventMicrostructure(validBody({ stages: shuffled }));
  assert.strictEqual(r.ok, true);
  const orders = r.value.stages.map((s) => s.order);
  assert.deepStrictEqual(orders, [0, 1, 2, 3, 4, 5, 6, 7, 8]);
  // First stage by time is the reminder fired (ts 1000), last is SYNC (ts 1020).
  assert.strictEqual(r.value.stages[0].type, DOSE_STAGE.REMINDER_FIRED);
  assert.strictEqual(r.value.stages[8].type, DOSE_STAGE.SYNC);
});

test("tokenization-ready shape: per-stage token TYPE@order + flat token_sequence", () => {
  const r = validateDoseEventMicrostructure(validBody());
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.value.stages[2].token, `${DOSE_STAGE.UNLOCK}@2`);
  assert.deepStrictEqual(
    r.value.token_sequence,
    r.value.stages.map((s) => `${s.type}@${s.order}`)
  );
  assert.strictEqual(r.value.token_sequence[0], "REMINDER_FIRED@0");
  assert.strictEqual(r.value.token_sequence.at(-1), "SYNC@8");
});

test("a versioned schema_version is stamped onto the normalized record", () => {
  const r = validateDoseEventMicrostructure(validBody());
  assert.strictEqual(r.ok, true);
  assert.strictEqual(typeof r.value.schema_version, "number");
  assert.strictEqual(r.value.schema_version, SCHEMA_VERSION);
});

test("reminder microbehavior (snooze + time-to-action) is captured and accepted", () => {
  const stages = fullStages();
  stages.splice(2, 0, {
    type: DOSE_STAGE.REMINDER_SNOOZED,
    timestamp: 1006,
    payload: { snooze_minutes: 10, time_to_action_ms: 1000 },
  });
  const r = validateDoseEventMicrostructure(validBody({ stages }));
  assert.strictEqual(r.ok, true);
  const snooze = r.value.stages.find((s) => s.type === DOSE_STAGE.REMINDER_SNOOZED);
  assert.strictEqual(snooze.payload.snooze_minutes, 10);
  assert.strictEqual(snooze.payload.time_to_action_ms, 1000);
});

// ----------------------------------------------------------------------------
// Rejection: out-of-order
// ----------------------------------------------------------------------------

test("out-of-order sequence (CAP_OPEN before UNLOCK by time) is rejected", () => {
  const stages = fullStages();
  // Swap timestamps so cap-open occurs before unlock physically.
  const unlock = stages.find((s) => s.type === DOSE_STAGE.UNLOCK);
  const capOpen = stages.find((s) => s.type === DOSE_STAGE.CAP_OPEN);
  unlock.timestamp = 1011;
  capOpen.timestamp = 1010;
  const r = validateDoseEventMicrostructure(validBody({ stages }));
  assert.strictEqual(r.ok, false);
  assert.match(r.error, /out-of-order/);
});

test("weigh-after before weigh-before (by time) is rejected as out-of-order", () => {
  const stages = fullStages();
  stages.find((s) => s.type === DOSE_STAGE.WEIGH_BEFORE).timestamp = 1013;
  stages.find((s) => s.type === DOSE_STAGE.WEIGH_AFTER).timestamp = 1012;
  const r = validateDoseEventMicrostructure(validBody({ stages }));
  assert.strictEqual(r.ok, false);
  assert.match(r.error, /out-of-order/);
});

// ----------------------------------------------------------------------------
// Rejection: missing stage / duplicate
// ----------------------------------------------------------------------------

test("missing a required backbone stage (SYNC) is rejected", () => {
  const stages = fullStages().filter((s) => s.type !== DOSE_STAGE.SYNC);
  const r = validateDoseEventMicrostructure(validBody({ stages }));
  assert.strictEqual(r.ok, false);
  assert.match(r.error, /missing required stage: SYNC/);
});

test("missing UNLOCK is rejected", () => {
  const stages = fullStages().filter((s) => s.type !== DOSE_STAGE.UNLOCK);
  const r = validateDoseEventMicrostructure(validBody({ stages }));
  assert.strictEqual(r.ok, false);
  assert.match(r.error, /missing required stage: UNLOCK/);
});

test("a duplicated required stage is rejected", () => {
  const stages = fullStages();
  stages.push({ type: DOSE_STAGE.CAP_CLOSE, timestamp: 1016, payload: {} });
  const r = validateDoseEventMicrostructure(validBody({ stages }));
  assert.strictEqual(r.ok, false);
  assert.match(r.error, /duplicate required stage: CAP_CLOSE/);
});

// ----------------------------------------------------------------------------
// Rejection: bad type / bad payload
// ----------------------------------------------------------------------------

test("an unknown stage type is rejected", () => {
  const stages = fullStages();
  stages[0] = { type: "NOT_A_STAGE", timestamp: 1000 };
  const r = validateDoseEventMicrostructure(validBody({ stages }));
  assert.strictEqual(r.ok, false);
});

test("a bad payload shape (negative weight) is rejected", () => {
  const stages = fullStages();
  stages.find((s) => s.type === DOSE_STAGE.WEIGH_BEFORE).payload = { weight_mg: -5 };
  const r = validateDoseEventMicrostructure(validBody({ stages }));
  assert.strictEqual(r.ok, false);
  assert.match(r.error, /Invalid payload for WEIGH_BEFORE/);
});

test("empty stages array is rejected", () => {
  const r = validateDoseEventMicrostructure(validBody({ stages: [] }));
  assert.strictEqual(r.ok, false);
});

// ----------------------------------------------------------------------------
// No-PHI invariant
// ----------------------------------------------------------------------------

test("no-PHI: a free-text string in a stage payload is rejected", () => {
  const stages = fullStages();
  // Attacker tries to smuggle a medication name into the weigh payload.
  stages.find((s) => s.type === DOSE_STAGE.WEIGH_AFTER).payload = {
    weight_mg: 4750,
    note: "Lisinopril 10mg for John Doe",
  };
  const r = validateDoseEventMicrostructure(validBody({ stages }));
  assert.strictEqual(r.ok, false);
  // Strict schema rejects the unknown field before the no-PHI guard even runs;
  // either way the free text never lands.
});

test("no-PHI: client_dose_id / idempotency_key reject free-text values", () => {
  const r1 = validateDoseEventMicrostructure(validBody({ client_dose_id: "patient John Doe" }));
  assert.strictEqual(r1.ok, false);
  const r2 = validateDoseEventMicrostructure(validBody({ idempotency_key: "med = Lisinopril" }));
  assert.strictEqual(r2.ok, false);
});

test("no-PHI: every accepted stage payload contains only numbers / enum codes", () => {
  const r = validateDoseEventMicrostructure(validBody());
  assert.strictEqual(r.ok, true);
  for (const stage of r.value.stages) {
    for (const [key, value] of Object.entries(stage.payload)) {
      const isCode = key === "channel" || key === "transport";
      assert.ok(
        typeof value === "number" || isCode,
        `stage ${stage.type} field ${key} must be a number or enum code, got ${typeof value}`
      );
    }
  }
});

// ----------------------------------------------------------------------------
// Condition-agnostic
// ----------------------------------------------------------------------------

test("condition-agnostic: normalized record carries no medication/condition field", () => {
  const r = validateDoseEventMicrostructure(validBody());
  assert.strictEqual(r.ok, true);
  const json = JSON.stringify(r.value).toLowerCase();
  for (const banned of ["medication", "medicine", "condition", "diagnosis", "drug"]) {
    assert.ok(!json.includes(banned), `record must not contain "${banned}"`);
  }
});
