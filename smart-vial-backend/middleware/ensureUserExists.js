//not in use##################################################################
/*
const User = require('../models/User');

/**
 * Middleware to ensure user exists in database
 * - Checks if user model exists for the user_id from the JWT token
 * - If not exists, creates a new user with the role from the token
 * - If exists, updates lastLogin and adds role if not already present
 * - Supports users having both 'user' and 'caregiver' roles
 */
const ensureUserExists = async (req, res, next) => {
  try {
    const user_id = req.user_id;
    const role = req.user_role; // from JWT token

    if (!user_id || !role) {
      return res.status(400).json({ error: 'Missing user_id or role in token' });
    }

    // Find or create user
    let user = await User.findOne({ user_id });

    if (!user) {
      // User doesn't exist, create new user with the role from token
      user = new User({
        user_id,
        user_roles: [role],
        claim_device_ids: [],
        caregiving_device_ids: [],
        createdAt: new Date(),
        lastLogin: new Date()
      });
      
      await user.save();
      console.log(`Created new user: ${user_id} with role: ${role}`);
    } else {
      // User exists, update lastLogin and ensure role is present
      user.lastLogin = new Date();
      
      // Add role if not already present
      if (!user.user_roles.includes(role)) {
        user.user_roles.push(role);
        console.log(`Added role '${role}' to user: ${user_id}`);
      }
      
      await user.save();
    }

    // Attach user object to request for use in controllers
    req.userModel = user;
    
    next();
  } catch (err) {
    console.error('Error in ensureUserExists middleware:', err.message);
    res.status(500).json({ error: 'Server error ensuring user exists' });
  }
};

module.exports = ensureUserExists;
