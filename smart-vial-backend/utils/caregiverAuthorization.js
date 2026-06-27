/**
 * GTM-507 — Server-authoritative caregiver authorization.
 *
 * Caregiver access used to be decided from `req.user_role` (a value the caller
 * can influence) combined with a find-or-create that ADDED the role on demand —
 * so a user could self-assign the caregiver role and reach another person's
 * device/adherence data.
 *
 * These helpers make the authorization decision depend ONLY on a trusted
 * server-side grant: the device owner (patient) explicitly assigned a caregiver
 * to a device, recorded on `device.caregiver_id` (and mirrored to a
 * CaregiverGrant record). The caller's asserted role is never consulted.
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
const GRANT_STATUS = Object.freeze({
  ACCEPTED: 'accepted',
  REVOKED: 'revoked',
});

module.exports = {
  isCaregiverAuthorizedForDevice,
  isDeviceOwner,
  GRANT_STATUS,
};
