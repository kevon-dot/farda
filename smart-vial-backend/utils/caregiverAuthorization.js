/**
 * GTM-507 — Server-authoritative caregiver authorization.
 *
 * Caregiver access used to be decided from `req.user_role` (a value the caller
 * can influence) combined with a find-or-create that ADDED the role on demand —
 * so a user could self-assign the caregiver role and reach another person's
 * device/adherence data.
 *
 * These helpers make the authorization decision depend ONLY on a trusted
 * server-side grant: the device owner (patient) explicitly invited a caregiver
 * to a device AND the caregiver explicitly accepted that invite. The accepted
 * relationship is recorded on `device.caregiver_id` (mirrored from an ACCEPTED
 * CaregiverGrant record). The caller's asserted role is never consulted.
 *
 * GTM-507-followup — two-sided consent state machine:
 *   (none) --invite(owner)--> pending --accept(caregiver)--> accepted
 *                                 |                              |
 *                                 +--------revoke(owner|cg)------+--> revoked
 *
 *   - A `pending` invite grants NOTHING: the caregiver has no access until they
 *     accept. `device.caregiver_id` is set ONLY once the grant is `accepted`.
 *   - `revoked` is terminal and cuts access (and clears `device.caregiver_id`).
 *   - Only the invited caregiver may accept. The owner OR the caregiver may
 *     revoke. Illegal transitions (e.g. accept on a revoked grant) are rejected.
 *
 * All functions are pure (no DB, no req) so they can be unit-tested without a
 * live MongoDB and reused by every caregiver-scoped handler.
 */

/**
 * Decide whether `caregiverUserId` is authorized for `device`, using ONLY the
 * server-side owner-granted relationship. Any client-supplied role is ignored.
 *
 * A caregiver is authorized for a device iff ALL of:
 *   - the device exists and is claimed by an owner,
 *   - the device's `caregiver_id` (set only by the owner) equals the caller, and
 *   - the caller is NOT the owner of the device (owners use the owner routes;
 *     this also prevents a self-claimed device masquerading as a caregiver grant).
 *
 * @param {Object} params
 * @param {string} params.caregiverUserId  authenticated caller id (req.user_id)
 * @param {{user_id: ?string, caregiver_id: ?string, claimed: ?boolean}|null} params.device
 * @returns {boolean}
 */
function isCaregiverAuthorizedForDevice({ caregiverUserId, device } = {}) {
  if (!caregiverUserId || typeof caregiverUserId !== 'string') return false;
  if (!device) return false;

  const ownerId = device.user_id || null;
  const grantedCaregiverId = device.caregiver_id || null;

  // Must be a real owner-granted relationship.
  if (!ownerId || !grantedCaregiverId) return false;
  // The grant must name THIS caller as the caregiver.
  if (grantedCaregiverId !== caregiverUserId) return false;
  // A caller cannot be both owner and caregiver of the same device; owners use
  // the owner-scoped routes. This blocks a self-claim being treated as a grant.
  if (ownerId === caregiverUserId) return false;

  return true;
}

/**
 * Decide whether `ownerUserId` may assign/revoke caregivers on `device`.
 * Only the trusted server-side owner of the device may do so. The caller cannot
 * grant themselves access to a device they do not own.
 *
 * @param {Object} params
 * @param {string} params.ownerUserId  authenticated caller id (req.user_id)
 * @param {{user_id: ?string}|null} params.device
 * @returns {boolean}
 */
function isDeviceOwner({ ownerUserId, device } = {}) {
  if (!ownerUserId || typeof ownerUserId !== 'string') return false;
  if (!device || !device.user_id) return false;
  return device.user_id === ownerUserId;
}

// Grant lifecycle states for the CaregiverGrant relationship/consent record.
//   pending  — owner invited a caregiver; consent not yet given; grants NOTHING.
//   accepted — caregiver consented; the relationship authorizes reads.
//   revoked  — terminal; access cut by owner or caregiver.
const GRANT_STATUS = Object.freeze({
  PENDING: 'pending',
  ACCEPTED: 'accepted',
  REVOKED: 'revoked',
});

/**
 * Decide whether `actorUserId` may ACCEPT `grant`. Two-sided consent: only the
 * invited CAREGIVER may accept, and only while the grant is still `pending`.
 * Accepting an already-accepted or revoked grant is an illegal transition.
 *
 * @param {Object} params
 * @param {string} params.actorUserId  authenticated caller id
 * @param {{caregiverUserId: ?string, status: ?string}|null} params.grant
 * @returns {{ok: boolean, reason?: string}}
 */
function canAcceptGrant({ actorUserId, grant } = {}) {
  if (!actorUserId || typeof actorUserId !== 'string') {
    return { ok: false, reason: 'invalid_actor' };
  }
  if (!grant || typeof grant !== 'object') {
    return { ok: false, reason: 'not_found' };
  }
  if (grant.status !== GRANT_STATUS.PENDING) {
    // accepted (already consented) or revoked (terminal) — no transition.
    return { ok: false, reason: 'illegal_transition' };
  }
  if (grant.caregiverUserId !== actorUserId) {
    // Only the invited caregiver consents on their own behalf.
    return { ok: false, reason: 'forbidden' };
  }
  return { ok: true };
}

/**
 * Decide whether `actorUserId` may REVOKE `grant`. Either the patient/owner who
 * extended the invite OR the caregiver themselves may revoke. Revoking is valid
 * from `pending` (withdraw/decline the invite) or `accepted` (end access).
 * Revoking an already-revoked grant is an illegal (no-op) transition.
 *
 * @param {Object} params
 * @param {string} params.actorUserId  authenticated caller id
 * @param {{patientUserId: ?string, caregiverUserId: ?string, status: ?string}|null} params.grant
 * @returns {{ok: boolean, reason?: string}}
 */
function canRevokeGrant({ actorUserId, grant } = {}) {
  if (!actorUserId || typeof actorUserId !== 'string') {
    return { ok: false, reason: 'invalid_actor' };
  }
  if (!grant || typeof grant !== 'object') {
    return { ok: false, reason: 'not_found' };
  }
  if (grant.status === GRANT_STATUS.REVOKED) {
    return { ok: false, reason: 'illegal_transition' };
  }
  const isOwner = grant.patientUserId === actorUserId;
  const isCaregiver = grant.caregiverUserId === actorUserId;
  if (!isOwner && !isCaregiver) {
    return { ok: false, reason: 'forbidden' };
  }
  return { ok: true };
}

module.exports = {
  isCaregiverAuthorizedForDevice,
  isDeviceOwner,
  canAcceptGrant,
  canRevokeGrant,
  GRANT_STATUS,
};
