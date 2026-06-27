const mongoose = require('mongoose');

const UserSchema = new mongoose.Schema({
  user_id:{
    type: String,
    required: true,
    unique: true,
    index: true,
  },
  user_roles:{
    type: [String],
    enum: ['caregiver', 'user'],
    default: [],
    validate: {
      validator: function(arr) {
        return arr.length > 0;
      },
      message: 'User must have at least one role'
    },
    index: true,
  },
  claim_device_ids: [{
    type: String,
    default: [],
    index: true,
  }],
  caregiving_device_ids: [{
    type: String,
    default: [],
    index: true,
  }],
  createdAt: {
    type: Date,
    default: Date.now,
  },
  lastLogin: {
    type: Date,
    default: Date.now,
  }
})

//  if user has a specific role
UserSchema.methods.hasRole = function(role) {
  return this.user_roles.includes(role);
};

//  add a role if not present
UserSchema.methods.addRole = function(role) {
  if (!this.user_roles.includes(role)) {
    this.user_roles.push(role);
  }
};

// to remove a role
UserSchema.methods.removeRole = function(role) {
  const index = this.user_roles.indexOf(role);
  if (index > -1) {
    this.user_roles.splice(index, 1);
  }
};

module.exports = mongoose.model('User', UserSchema);