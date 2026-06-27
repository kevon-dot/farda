// ============================================
// GTM-539 — semver + OTA resolution (PURE, no MongoDB)
// ============================================

const test = require("node:test");
const assert = require("node:assert");

const { parseSemver, compareSemver, isNewer, gte, isValidSemver } = require("../utils/semver");
const {
  resolveUpdateForDevice,
  releaseTargetsDevice,
  ROLLOUT_STATE,
} = require("../utils/otaResolution");

// ---------------------------------------------------------------------------
// semver
// ---------------------------------------------------------------------------

test("parseSemver handles v-prefix and pre-release/build suffixes", () => {
  assert.deepStrictEqual(parseSemver("1.4.2"), { major: 1, minor: 4, patch: 2 });
  assert.deepStrictEqual(parseSemver("v2.0.0"), { major: 2, minor: 0, patch: 0 });
  assert.deepStrictEqual(parseSemver("1.4.2-rc1"), { major: 1, minor: 4, patch: 2 });
  assert.deepStrictEqual(parseSemver("1.4.2+abc123"), { major: 1, minor: 4, patch: 2 });
  assert.strictEqual(parseSemver("not-a-version"), null);
  assert.strictEqual(parseSemver("1.2"), null);
});

test("compareSemver orders correctly and sorts garbage below valid", () => {
  assert.ok(compareSemver("1.0.0", "1.0.1") < 0);
  assert.ok(compareSemver("1.2.0", "1.10.0") < 0); // numeric, not lexicographic
  assert.ok(compareSemver("2.0.0", "1.9.9") > 0);
  assert.strictEqual(compareSemver("1.2.3", "1.2.3"), 0);
  assert.ok(compareSemver("garbage", "0.0.1") < 0);
  assert.ok(isNewer("1.0.1", "1.0.0"));
  assert.ok(gte("1.0.0", "1.0.0"));
  assert.ok(isValidSemver("3.1.4"));
  assert.ok(!isValidSemver("3.1"));
});

// ---------------------------------------------------------------------------
// OTA resolution
// ---------------------------------------------------------------------------

function release(overrides = {}) {
  return {
    version: "1.1.0",
    image_url: "https://cdn.example.com/fw/1.1.0.bin",
    image_ref: "fw/1.1.0",
    image_sha256: null,
    min_version: null,
    rollout_state: ROLLOUT_STATE.ACTIVE,
    target_device_ids: [],
    target_cohorts: [],
    created_at: "2026-01-01T00:00:00Z",
    ...overrides,
  };
}

test("offers the newest active release when device is behind", () => {
  const result = resolveUpdateForDevice({
    device: { device_id: "D1", firmware_version: "1.0.0" },
    releases: [release({ version: "1.1.0" }), release({ version: "1.2.0" })],
  });
  assert.strictEqual(result.update_available, true);
  assert.strictEqual(result.version, "1.2.0");
  assert.ok(/^https:\/\//.test(result.image_url));
  assert.strictEqual(result.is_rollback, false);
});

test("no update when device is already on (or above) the newest release", () => {
  const result = resolveUpdateForDevice({
    device: { device_id: "D1", firmware_version: "1.2.0" },
    releases: [release({ version: "1.2.0" })],
  });
  assert.strictEqual(result.update_available, false);
});

test("never offers a downgrade for a normal (unpinned) device", () => {
  const result = resolveUpdateForDevice({
    device: { device_id: "D1", firmware_version: "2.0.0" },
    releases: [release({ version: "1.5.0" })],
  });
  assert.strictEqual(result.update_available, false);
});

test("respects min_version: a too-old device is NOT offered the release", () => {
  const releases = [release({ version: "2.0.0", min_version: "1.5.0" })];
  const tooOld = resolveUpdateForDevice({
    device: { device_id: "D1", firmware_version: "1.0.0" },
    releases,
  });
  assert.strictEqual(tooOld.update_available, false);

  const reachable = resolveUpdateForDevice({
    device: { device_id: "D1", firmware_version: "1.6.0" },
    releases,
  });
  assert.strictEqual(reachable.update_available, true);
  assert.strictEqual(reachable.version, "2.0.0");
});

test("draft / paused releases are not auto-offered", () => {
  for (const state of [ROLLOUT_STATE.DRAFT, ROLLOUT_STATE.PAUSED, ROLLOUT_STATE.COMPLETED]) {
    const result = resolveUpdateForDevice({
      device: { device_id: "D1", firmware_version: "1.0.0" },
      releases: [release({ version: "1.2.0", rollout_state: state })],
    });
    assert.strictEqual(result.update_available, false, `state=${state}`);
  }
});

test("staged rollout: only targeted device ids / cohorts are offered", () => {
  const releases = [
    release({
      version: "1.3.0",
      rollout_state: ROLLOUT_STATE.STAGED,
      target_device_ids: ["D1"],
      target_cohorts: ["beta"],
    }),
  ];
  // Targeted by id.
  assert.strictEqual(
    resolveUpdateForDevice({
      device: { device_id: "D1", firmware_version: "1.0.0" },
      releases,
    }).update_available,
    true
  );
  // Targeted by cohort.
  assert.strictEqual(
    resolveUpdateForDevice({
      device: { device_id: "D9", firmware_version: "1.0.0", cohort: "beta" },
      releases,
    }).update_available,
    true
  );
  // Not in either ⇒ no update.
  assert.strictEqual(
    resolveUpdateForDevice({
      device: { device_id: "D9", firmware_version: "1.0.0", cohort: "ga" },
      releases,
    }).update_available,
    false
  );
});

test("pin: serves the pinned release even if it is older (rollback)", () => {
  const releases = [
    release({ version: "1.0.0" }),
    release({ version: "2.0.0" }),
  ];
  const result = resolveUpdateForDevice({
    device: {
      device_id: "D1",
      firmware_version: "2.0.0",
      pinned_release_version: "1.0.0",
    },
    releases,
  });
  assert.strictEqual(result.update_available, true);
  assert.strictEqual(result.version, "1.0.0");
  assert.strictEqual(result.is_rollback, true);
});

test("pin: a device already on the pinned version gets no update", () => {
  const result = resolveUpdateForDevice({
    device: {
      device_id: "D1",
      firmware_version: "1.0.0",
      pinned_release_version: "1.0.0",
    },
    releases: [release({ version: "1.0.0" })],
  });
  assert.strictEqual(result.update_available, false);
  assert.strictEqual(result.reason, "already_on_pinned");
});

test("pin: a forward pin (single-device staged rollout) is offered", () => {
  const result = resolveUpdateForDevice({
    device: {
      device_id: "D1",
      firmware_version: "1.0.0",
      pinned_release_version: "1.5.0",
    },
    releases: [release({ version: "1.5.0", rollout_state: ROLLOUT_STATE.DRAFT })],
  });
  // Even a DRAFT release is reachable via an explicit pin.
  assert.strictEqual(result.update_available, true);
  assert.strictEqual(result.version, "1.5.0");
  assert.strictEqual(result.is_rollback, false);
});

test("pin to an unknown version yields no update (fail closed)", () => {
  const result = resolveUpdateForDevice({
    device: { device_id: "D1", firmware_version: "1.0.0", pinned_release_version: "9.9.9" },
    releases: [release({ version: "1.1.0" })],
  });
  assert.strictEqual(result.update_available, false);
  assert.strictEqual(result.reason, "pinned_release_not_found");
});

test("releaseTargetsDevice: active targets everyone, staged only matches", () => {
  assert.ok(
    releaseTargetsDevice(release({ rollout_state: ROLLOUT_STATE.ACTIVE }), { device_id: "X" })
  );
  assert.ok(
    !releaseTargetsDevice(
      release({ rollout_state: ROLLOUT_STATE.STAGED, target_device_ids: [] }),
      { device_id: "X" }
    )
  );
});
