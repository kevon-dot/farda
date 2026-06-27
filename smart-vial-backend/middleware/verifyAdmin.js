// ============================================
// GTM-539 — Admin authorization (server-authoritative)
// ============================================
// Fleet-wide registry / OTA / health endpoints are ADMIN-ONLY. Admin status is
// decided SERVER-SIDE against config.admin.userIds (the ADMIN_USER_IDS env
// allowlist), NEVER from a client-asserted role/header — mirroring the
// server-authoritative pattern used for caregiver grants (GTM-507).
//
// This middleware does NOT re-implement session verification: it runs AFTER
// verifyUserToken (which populates req.user_id from the better-auth session)
// and simply gates on the allowlist. Fails closed: an empty allowlist denies
// everyone.

const config = require("../config/config");

/**
 * Pure check: is this user id an allow-listed admin?
 * @param {string} userId
 * @param {string[]} [adminUserIds]
 * @returns {boolean}
 */
function isAdminUser(userId, adminUserIds = config.admin.userIds) {
  if (!userId || typeof userId !== "string") return false;
  if (!Array.isArray(adminUserIds) || adminUserIds.length === 0) return false;
  return adminUserIds.includes(userId);
}

/**
 * Express middleware. MUST be mounted after verifyUserToken so req.user_id is
 * set. Returns 403 for an authenticated-but-non-admin caller.
 */
const verifyAdmin = (req, res, next) => {
  if (!req.user_id) {
    // verifyUserToken should have set this; if not, treat as unauthenticated.
    return res.status(401).json({ error: "Access Denied: authentication required" });
  }
  if (!isAdminUser(req.user_id)) {
    return res.status(403).json({ error: "Access Denied: admin privileges required" });
  }
  return next();
};

module.exports = verifyAdmin;
module.exports.isAdminUser = isAdminUser;
