const test = require("node:test");
const assert = require("node:assert");

const {
  isCaregiverAuthorizedForDevice,
  isDeviceOwner,
  GRANT_STATUS,
} = require("../utils/caregiverAuthorization");

// Self-contained: no MongoDB / Postgres / network required. Exercises the pure
// server-authoritative authorization rules introduced for GTM-507.

// ============================================
// GTM-507 — caregiver authorization is decided ONLY by the owner-granted
// relationship on the device, never by any caller-supplied role.
// ============================================

test("caregiver WITHOUT a grant is denied", () => {
  const device = { user_id: "owner_1", caregiver_id: null, claimed: true };
  assert.strictEqual(
    isCaregiverAuthorizedForDevice({ caregiverUserId: "cg_1", device }),
    false
  );
});

test("caregiver WITH an accepted grant (device.caregiver_id) is allowed", () => {
  const device = { user_id: "owner_1", caregiver_id: "cg_1", claimed: true };
  assert.strictEqual(
    isCaregiverAuthorizedForDevice({ caregiverUserId: "cg_1", device }),
    true
  );
});

test("a different caregiver than the one granted is denied", () => {
  const device = { user_id: "owner_1", caregiver_id: "cg_1", claimed: true };
  assert.strictEqual(
    isCaregiverAuthorizedForDevice({ caregiverUserId: "cg_OTHER", device }),
    false
  );
});

test("a user cannot self-assign caregiver authority over a device they don't own", () => {
  // attacker is neither the owner nor the granted caregiver — no relationship.
  const device = { user_id: "owner_1", caregiver_id: "cg_1", claimed: true };
  assert.strictEqual(
    isCaregiverAuthorizedForDevice({ caregiverUserId: "attacker", device }),
    false
  );
});

test("owner cannot be treated as caregiver of their own device (self-grant blocked)", () => {
  // Even if caregiver_id somehow equals the owner, that is not a caregiver grant.
  const device = { user_id: "same", caregiver_id: "same", claimed: true };
  assert.strictEqual(
    isCaregiverAuthorizedForDevice({ caregiverUserId: "same", device }),
    false
  );
});

test("unclaimed device with no owner cannot be caregiver-accessed", () => {
  const device = { user_id: null, caregiver_id: "cg_1", claimed: false };
  assert.strictEqual(
    isCaregiverAuthorizedForDevice({ caregiverUserId: "cg_1", device }),
    false
  );
});

test("authorization helper is server-authoritative: ignores any client-supplied role", () => {
  // The helper has no role parameter at all. A caller asserting any role is
  // irrelevant — only the server-side device grant decides access.
  const device = { user_id: "owner_1", caregiver_id: null, claimed: true };

  // Simulate a client trying to smuggle a role in alongside the call. The extra
  // property is simply ignored; without a grant the caller is denied.
  assert.strictEqual(
    isCaregiverAuthorizedForDevice({
      caregiverUserId: "cg_1",
      device,
      user_role: "caregiver",
      role: "caregiver",
    }),
    false
  );

  // And WITH a real grant, the decision is the same regardless of asserted role.
  const granted = { user_id: "owner_1", caregiver_id: "cg_1", claimed: true };
  assert.strictEqual(
    isCaregiverAuthorizedForDevice({
      caregiverUserId: "cg_1",
      device: granted,
      user_role: "user",
    }),
    true
  );
});

test("missing/invalid inputs are denied", () => {
  assert.strictEqual(isCaregiverAuthorizedForDevice(), false);
  assert.strictEqual(isCaregiverAuthorizedForDevice({}), false);
  assert.strictEqual(
    isCaregiverAuthorizedForDevice({ caregiverUserId: "", device: { user_id: "o", caregiver_id: "" } }),
    false
  );
  assert.strictEqual(
    isCaregiverAuthorizedForDevice({ caregiverUserId: { $ne: null }, device: { user_id: "o", caregiver_id: "x" } }),
    false
  );
});

// ============================================
// GTM-507 — only the trusted device owner may grant/revoke caregivers.
// ============================================

test("isDeviceOwner is true only for the real owner", () => {
  const device = { user_id: "owner_1" };
  assert.strictEqual(isDeviceOwner({ ownerUserId: "owner_1", device }), true);
  assert.strictEqual(isDeviceOwner({ ownerUserId: "someone_else", device }), false);
});

test("isDeviceOwner denies when device has no owner or inputs missing", () => {
  assert.strictEqual(isDeviceOwner({ ownerUserId: "x", device: { user_id: null } }), false);
  assert.strictEqual(isDeviceOwner({ ownerUserId: "x", device: null }), false);
  assert.strictEqual(isDeviceOwner({}), false);
});

test("GRANT_STATUS exposes accepted/revoked lifecycle states", () => {
  assert.strictEqual(GRANT_STATUS.ACCEPTED, "accepted");
  assert.strictEqual(GRANT_STATUS.REVOKED, "revoked");
});
