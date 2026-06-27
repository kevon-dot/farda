const User = require('../models/User');

/**
 * Find the user record for `user_id`, creating it (persisted) if it does not
 * exist. When it already exists, `role` is added to its roles if missing.
 *
 * This consolidates the find-or-create logic that was previously copy-pasted
 * into every caregiver handler. The returned document is always persisted.
 *
 * @param {string} user_id  the authenticated user id (from the verified token)
 * @param {string} role     the role to ensure the user has (e.g. 'caregiver')
 * @returns {Promise<import('mongoose').Document>} the persisted user document
 */
const findOrCreateUser = async (user_id, role) => {
  let user = await User.findOne({ user_id });

  if (!user) {
    user = new User({
      user_id,
      user_roles: role ? [role] : ['user'],
      claim_device_ids: [],
      caregiving_device_ids: [],
    });
    await user.save();
    return user;
  }

  let dirty = false;
  if (role && !user.user_roles.includes(role)) {
    user.user_roles.push(role);
    dirty = true;
  }
  if (dirty) {
    await user.save();
  }
  return user;
};

module.exports = { findOrCreateUser };
