// ============================================
// GTM-519 — Dose-event microstructure validation
// ============================================
// A dose-event MICROSTRUCTURE is the typed, ordered, server-authoritative record
// of ONE full physical dose interaction, captured at fine granularity: the
// reminder(s) that fired and how the patient reacted, the cap unlock, the cap
// open, the weigh-before / weigh-after / weight-delta, the cap close, and the
// final sync. The raw firmware/app ingest path (GTM-514, models/Event.js) lands
// coarse device events; THIS structure stitches one dose's stages into a single,
// tokenization-ready, ordered record.
//
// Design constraints (do not relax without bumping SCHEMA_VERSION):
//   1. TYPED + ORDERED. Stages are a fixed enum with a canonical ordinal. The
//      server — never the client — decides ordering. Clients send stages with
//      device timestamps; we sort by device timestamp, assign a contiguous
//      0..N-1 `order`, and stamp a single server `recordedAt`.
//   2. CONDITION-AGNOSTIC. Nothing here references a medication, condition, or
//      regimen. The structure describes the mechanics of a dose interaction only.
//   3. TOKENIZATION-READY. Each stage carries a stable `token` (TYPE@order) and
//      the record exposes a flat ordered `token` sequence so a downstream model
//      can consume it directly. Versioned via SCHEMA_VERSION for forward compat.
//   4. NO PHI. Subjects are referenced by id only (device id derived from the
//      session-owned device, never a name/medication string). A guard rejects
//      any free-text-looking field in a stage payload.
//
// Wire body (one full microstructure per request; see controller):
//   {
//     client_dose_id: "uuid",        // app-local correlation id (opaque, not PHI)
//     idempotency_key: "hash",       // client-computed stable hash for dedupe
//     stages: [                      // UNORDERED on the wire; server orders them
//       { type: "REMINDER_FIRED", timestamp: 1738483200, payload: {...} },
//       { type: "UNLOCK",         timestamp: 1738483260 },
//       ...
//     ]
//   }

const { z } = require("zod");

// ---------------------------------------------------------------------------
// Schema version. Bump on ANY change to stage types, ordinals, or payload
// shapes so persisted records (and downstream tokenizers) can be migrated.
// ---------------------------------------------------------------------------
const SCHEMA_VERSION = 1;

// ---------------------------------------------------------------------------
// Stage types — the stable, typed, ordered event-type enum.
//
// `ORDINAL` defines the canonical lifecycle order. The server sorts incoming
// stages by device timestamp and then asserts the resulting type order is a
// non-decreasing walk through these ordinals (an out-of-order sequence — e.g.
// CAP_OPEN before UNLOCK — is rejected). REMINDER_* stages all share ordinal 0:
// any number of them may precede the interaction, in any internal order.
// ---------------------------------------------------------------------------
const DOSE_STAGE = Object.freeze({
  REMINDER_FIRED: "REMINDER_FIRED",
  REMINDER_OPENED: "REMINDER_OPENED",
  REMINDER_SNOOZED: "REMINDER_SNOOZED",
  REMINDER_DISMISSED: "REMINDER_DISMISSED",
  UNLOCK: "UNLOCK",
  CAP_OPEN: "CAP_OPEN",
  WEIGH_BEFORE: "WEIGH_BEFORE",
  WEIGH_AFTER: "WEIGH_AFTER",
  WEIGHT_DELTA: "WEIGHT_DELTA",
  CAP_CLOSE: "CAP_CLOSE",
  SYNC: "SYNC",
});

const DOSE_STAGE_TYPES = Object.freeze(Object.values(DOSE_STAGE));

// Canonical lifecycle ordinal per stage type. Reminder microbehaviors collapse
// to the pre-interaction phase (0). The interaction then walks monotonically.
const STAGE_ORDINAL = Object.freeze({
  [DOSE_STAGE.REMINDER_FIRED]: 0,
  [DOSE_STAGE.REMINDER_OPENED]: 0,
  [DOSE_STAGE.REMINDER_SNOOZED]: 0,
  [DOSE_STAGE.REMINDER_DISMISSED]: 0,
  [DOSE_STAGE.UNLOCK]: 1,
  [DOSE_STAGE.CAP_OPEN]: 2,
  [DOSE_STAGE.WEIGH_BEFORE]: 3,
  [DOSE_STAGE.WEIGH_AFTER]: 4,
  [DOSE_STAGE.WEIGHT_DELTA]: 5,
  [DOSE_STAGE.CAP_CLOSE]: 6,
  [DOSE_STAGE.SYNC]: 7,
});

// The mandatory interaction backbone. A well-formed microstructure MUST contain
// every one of these exactly once (reminder stages are optional context around
// it). Missing any required stage rejects the whole record.
const REQUIRED_STAGES = Object.freeze([
  DOSE_STAGE.UNLOCK,
  DOSE_STAGE.CAP_OPEN,
  DOSE_STAGE.WEIGH_BEFORE,
  DOSE_STAGE.WEIGH_AFTER,
  DOSE_STAGE.WEIGHT_DELTA,
  DOSE_STAGE.CAP_CLOSE,
  DOSE_STAGE.SYNC,
]);

// Reminder microbehavior stages (the optional, repeatable pre-interaction set).
const REMINDER_STAGES = Object.freeze([
  DOSE_STAGE.REMINDER_FIRED,
  DOSE_STAGE.REMINDER_OPENED,
  DOSE_STAGE.REMINDER_SNOOZED,
  DOSE_STAGE.REMINDER_DISMISSED,
]);

// ---------------------------------------------------------------------------
// Per-stage payload schemas. Strict (NOT passthrough) so an unexpected field —
// the most common way PHI leaks in — is rejected. Every field below is a number
// or a constrained code; none can carry a name/medication/free-text string.
// ---------------------------------------------------------------------------

// Reminder microbehavior. `time_to_action_ms` is the latency from the reminder
// firing to the patient acting on it; `snooze_minutes` only for SNOOZED.
const reminderPayload = z
  .object({
    reminder_index: z.number().int().nonnegative().optional(),
    time_to_action_ms: z.number().int().nonnegative().optional(),
    snooze_minutes: z.number().int().positive().optional(),
    channel: z.enum(["LOCAL", "PUSH"]).optional(),
  })
  .strict();

const unlockPayload = z.object({}).strict();

const capPayload = z
  .object({
    duration_ms: z.number().int().nonnegative().optional(),
  })
  .strict();

// Weights are in milligrams (integer) — a number, never a label.
const weighPayload = z
  .object({
    weight_mg: z.number().nonnegative(),
  })
  .strict();

const weightDeltaPayload = z
  .object({
    delta_mg: z.number(),
  })
  .strict();

const syncPayload = z
  .object({
    transport: z.enum(["BLE", "WIFI", "RELAY"]).optional(),
  })
  .strict();

const STAGE_PAYLOADS = Object.freeze({
  [DOSE_STAGE.REMINDER_FIRED]: reminderPayload,
  [DOSE_STAGE.REMINDER_OPENED]: reminderPayload,
  [DOSE_STAGE.REMINDER_SNOOZED]: reminderPayload,
  [DOSE_STAGE.REMINDER_DISMISSED]: reminderPayload,
  [DOSE_STAGE.UNLOCK]: unlockPayload,
  [DOSE_STAGE.CAP_OPEN]: capPayload,
  [DOSE_STAGE.WEIGH_BEFORE]: weighPayload,
  [DOSE_STAGE.WEIGH_AFTER]: weighPayload,
  [DOSE_STAGE.WEIGHT_DELTA]: weightDeltaPayload,
  [DOSE_STAGE.CAP_CLOSE]: capPayload,
  [DOSE_STAGE.SYNC]: syncPayload,
});

// ---------------------------------------------------------------------------
// Wire schema for a single incoming stage.
// ---------------------------------------------------------------------------
const incomingStageSchema = z.object({
  type: z.enum(DOSE_STAGE_TYPES),
  // Unix seconds from the device. The SERVER decides ordering from this — it is
  // never trusted as the canonical record time (that's `recordedAt`, server set).
  timestamp: z.number().finite(),
  payload: z.unknown().optional(),
});

// `client_dose_id` / `idempotency_key` are opaque correlation strings, not PHI.
// They are constrained to id-like tokens so a free-text value can't sneak in.
const idLike = z
  .string()
  .min(1)
  .max(128)
  .regex(/^[A-Za-z0-9._:-]+$/, "must be an opaque id (no free text / PHI)");

const microstructureSchema = z.object({
  client_dose_id: idLike,
  idempotency_key: idLike,
  stages: z.array(incomingStageSchema).min(1, "stages must not be empty"),
});

// ---------------------------------------------------------------------------
// No-PHI guard. Defense-in-depth on top of the strict per-stage schemas: scan a
// parsed payload for any string value (every legitimate payload field is a
// number or a constrained enum code) and reject it. This makes "no free-text in
// the event body" a hard, testable invariant rather than a convention.
// ---------------------------------------------------------------------------
function assertNoPhi(payload) {
  for (const [key, value] of Object.entries(payload || {})) {
    if (typeof value === "string") {
      // Enum-coded fields are allowed (channel/transport); they are validated by
      // the strict schema to a small fixed set and carry no patient data.
      if (key === "channel" || key === "transport") continue;
      return {
        ok: false,
        error: `stage payload field "${key}" is a string; event body must be PHI-free (ids/codes/numbers only)`,
      };
    }
    if (value && typeof value === "object") {
      return {
        ok: false,
        error: `stage payload field "${key}" is a nested object; event body must be flat and PHI-free`,
      };
    }
  }
  return { ok: true };
}

function formatZodError(error) {
  return error.issues
    .map((i) => {
      const path = i.path.length ? `${i.path.join(".")}: ` : "";
      return `${path}${i.message}`;
    })
    .join("; ");
}

// ---------------------------------------------------------------------------
// validateDoseEventMicrostructure
//
// Pure validation + server-authoritative normalization of a dose-event
// microstructure body. On success returns a fully-ordered, tokenization-ready
// record (minus the device/subject id and recordedAt, which the controller binds
// from the session-owned device + server clock).
//
// @param {*} body raw req.body
// @returns {{ ok: true, value: { client_dose_id, idempotency_key, schema_version,
//            stages: Array<{ type, order, device_timestamp, payload, token }>,
//            token_sequence: string[] } }
//          | { ok: false, error: string }}
// ---------------------------------------------------------------------------
function validateDoseEventMicrostructure(body) {
  const base = microstructureSchema.safeParse(body);
  if (!base.success) {
    return { ok: false, error: formatZodError(base.error) };
  }
  const data = base.data;

  // 1. Validate + normalize each stage's payload against its strict schema and
  //    the no-PHI guard. Collect device timestamps for server-side ordering.
  const normalized = [];
  for (const stage of data.stages) {
    const schema = STAGE_PAYLOADS[stage.type];
    const rawPayload =
      stage.payload === undefined || stage.payload === null ? {} : stage.payload;
    const parsed = schema.safeParse(rawPayload);
    if (!parsed.success) {
      return {
        ok: false,
        error: `Invalid payload for ${stage.type}: ${formatZodError(parsed.error)}`,
      };
    }
    const phi = assertNoPhi(parsed.data);
    if (!phi.ok) {
      return { ok: false, error: phi.error };
    }
    normalized.push({
      type: stage.type,
      device_timestamp: stage.timestamp,
      payload: parsed.data,
    });
  }

  // 2. Completeness: every required backbone stage present exactly once.
  for (const required of REQUIRED_STAGES) {
    const count = normalized.filter((s) => s.type === required).length;
    if (count === 0) {
      return { ok: false, error: `missing required stage: ${required}` };
    }
    if (count > 1) {
      return { ok: false, error: `duplicate required stage: ${required}` };
    }
  }

  // 3. SERVER-AUTHORITATIVE ORDERING. Never trust the client's array order: sort
  //    by device timestamp (stable for ties). The resulting type order must be a
  //    non-decreasing walk through the canonical ordinals — otherwise the device
  //    reported a physically-impossible sequence (e.g. CAP_OPEN before UNLOCK)
  //    and the whole record is rejected.
  const ordered = normalized
    .map((s, i) => ({ ...s, _i: i }))
    .sort((a, b) =>
      a.device_timestamp !== b.device_timestamp
        ? a.device_timestamp - b.device_timestamp
        : a._i - b._i
    );

  let prevOrdinal = -1;
  for (const stage of ordered) {
    const ord = STAGE_ORDINAL[stage.type];
    // Within the same ordinal (reminder microbehaviors) any order is fine; a
    // strictly-smaller ordinal after a larger one is an illegal sequence.
    if (ord < prevOrdinal) {
      return {
        ok: false,
        error: `out-of-order stage ${stage.type}: lifecycle stage cannot follow a later stage`,
      };
    }
    prevOrdinal = ord;
  }

  // 4. Assign the contiguous server `order` and build the tokenization-ready
  //    shape. `token` is TYPE@order; `token_sequence` is the flat ordered list a
  //    downstream model consumes directly.
  const stages = ordered.map((s, order) => ({
    type: s.type,
    order,
    device_timestamp: s.device_timestamp,
    payload: s.payload,
    token: `${s.type}@${order}`,
  }));

  return {
    ok: true,
    value: {
      client_dose_id: data.client_dose_id,
      idempotency_key: data.idempotency_key,
      schema_version: SCHEMA_VERSION,
      stages,
      token_sequence: stages.map((s) => s.token),
    },
  };
}

module.exports = {
  SCHEMA_VERSION,
  DOSE_STAGE,
  DOSE_STAGE_TYPES,
  STAGE_ORDINAL,
  REQUIRED_STAGES,
  REMINDER_STAGES,
  STAGE_PAYLOADS,
  validateDoseEventMicrostructure,
};
