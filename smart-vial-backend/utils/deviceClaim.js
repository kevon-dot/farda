/**
 * Pure state-transition helpers for the device claim/unclaim flow.
 *
 * These operate on plain shapes so they can be unit-tested without a live
 * MongoDB. The HTTP handlers mutate the Mongoose documents/arrays in the same
 * way and persist them; keeping the transition logic here makes the
 * "unclaim must leave no stale caregiver link" invariant explicit and tested.
 */

/**
 * Compute the fields to clear on a device when it is unclaimed. Unclaiming
 * fully detaches BOTH the owner and any caregiver so the device can be cleanly
 * re-claimed and re-assigned.
 *
 * @param {{user_id: string|null, claimed: boolean, caregiver_id: string|null}} device
 * @returns {{user_id: null, claimed: false, caregiver_id: null, previousCaregiverId: string|null}}
 */
function computeUnclaimDeviceState(device) {
  return {
    user_id: null,
    claimed: false,
    caregiver_id: null,
    // Surfaced so the caller knows which caregiver's caregiving_device_ids to clean.
    previousCaregiverId: device ? device.caregiver_id || null : null,
  };
}

/**
 * Remove `device_id` from a list of device ids (caregiving_device_ids or
 * claim_device_ids). Returns a new array; does not mutate the input.
 *
 * @param {string[]} deviceIds
 * @param {string} device_id
 * @returns {string[]}
 */
function removeDeviceId(deviceIds, device_id) {
  if (!Array.isArray(deviceIds)) return [];
  return deviceIds.filter((id) => id !== device_id);
}

module.exports = { computeUnclaimDeviceState, removeDeviceId };
