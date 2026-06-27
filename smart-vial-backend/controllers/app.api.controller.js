const Device = require("../models/Device");
const Event = require("../models/Event");
const User = require("../models/User");
const CaregiverGrant = require("../models/CaregiverGrant");
const { computeUnclaimDeviceState, removeDeviceId } = require("../utils/deviceClaim");
const { GRANT_STATUS } = require("../utils/caregiverAuthorization");

//save user to database
const saveUser = async (req, res, next) => {
  try {
    const user_id = req.user_id;
    const user_role = req.user_role;

    // Find or create user
    let user = await User.findOne({ user_id });

    if (!user) {
      // Create new user
      user = new User({
        user_id,
        user_roles: [user_role],
        claim_device_ids: [],
        caregiving_device_ids: [],
        createdAt: new Date(),
        lastLogin: new Date()
      });
      await user.save();
      return res.status(201).json({ 
        status: "success", 
        message: "User created successfully",
        user: {
          user_id: user.user_id,
          user_roles: user.user_roles,
          createdAt: user.createdAt,
          lastLogin: user.lastLogin
        }
      });
    } else {
      // Update existing user
      user.lastLogin = new Date();
      
      // Add role if not already present
      if (!user.user_roles.includes(user_role)) {
        user.user_roles.push(user_role);
      }
      
      await user.save();
      return res.status(200).json({ 
        status: "success", 
        message: "User updated successfully",
        user: {
          user_id: user.user_id,
          user_roles: user.user_roles,
          claim_device_ids: user.claim_device_ids,
          caregiving_device_ids: user.caregiving_device_ids,
          createdAt: user.createdAt,
          lastLogin: user.lastLogin
        }
      });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

//save a device for a user logic
const claimDevice =  async (req, res, next) => {
  try {
    const { device_id } = req.body;
    const user_id = req.user_id;
    const user_role = req.user_role;

    const device = await Device.findOne({ device_id });

    if (!device) {
      return res
        .status(404)
        .json({ error: "Device invalid (not provisioned)" });
    }

    if (device.claimed || device.user_id) {
      return res
        .status(409)
        .json({ error: "Device is already claimed by another user" });
    }

    device.user_id = user_id;
    device.claimed = true;
    await device.save();

    // Find or create user and add device_id to claim_device_ids
    let user = await User.findOne({ user_id });
    
    if (!user) {
      // Create new user if doesn't exist
      user = new User({
        user_id,
        user_roles: [user_role],
        claim_device_ids: [device_id],
        caregiving_device_ids: []
      });
    } else {
      // Add role if not present
      if (!user.user_roles.includes(user_role)) {
        user.user_roles.push(user_role);
      }
      // Add device_id if not already present
      if (!user.claim_device_ids.includes(device_id)) {
        user.claim_device_ids.push(device_id);
      }
      user.lastLogin = new Date();
    }
    
    await user.save();

    res.json({ status: "success", device });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

//get all devices for a user logic 
const  getUserDevices = async (req, res, next) => {
  try {
    const devices = await Device.find({ user_id: req.user_id });
    res.json(devices);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

//get single device event logic
const getADeviceEvents = async (req, res, next) => {
    try {
      const { device_id } = req.params;
      const device = await Device.findOne({ device_id, user_id: req.user_id });
      if (!device) {
        return res.status(404).json({ error: "Device not found" });
      }

      const events = await Event.find({ device_id })
        .sort({ server_timestamp: -1 })
        .limit(100);
      res.json(events);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  };

//get all devices events logic
const getAllDevicesEvents = async (req, res, next) => {
  try {
    const devices = await Device.find({ user_id: req.user_id });
    
    if (devices.length === 0) {
      return res.json([]);
    }

    const deviceIds = devices.map(device => device.device_id);
    const events = await Event.find({ device_id: { $in: deviceIds } })
      .sort({ server_timestamp: -1 })
      .limit(500);
    
    res.json(events);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// get search device events logic by time range
const searchDeviceEventsByTimeRange = async (req, res, next) => {
  try {
    const { device_id } = req.params;
    const { start_time, end_time } = req.query;

    if (!start_time || !end_time) {
      return res.status(400).json({ error: "start_time and end_time are required" });
    }

    const device = await Device.findOne({ device_id, user_id: req.user_id });
    if (!device) {
      return res.status(404).json({ error: "Device not found" });
    }

    const events = await Event.find({
      device_id,
      server_timestamp: {
        $gte: new Date(start_time),
        $lte: new Date(end_time)
      }
    }).sort({ server_timestamp: -1 });
    
    res.json(events);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

//remove claimed device logic
const removeClaimedDevice = async (req, res, next) => {
  try {
    const { device_id } = req.params;
    const user_id = req.user_id;

    const device = await Device.findOne({ device_id, user_id });

    if (!device) {
      return res.status(404).json({ error: "Device not found" });
    }

    // Fully detach the device: clear the owner AND any caregiver assignment so
    // it can be cleanly re-claimed and re-assigned. Capture the previous
    // caregiver before clearing so we can also clean up their link below.
    const { user_id: nextUserId, claimed, caregiver_id, previousCaregiverId } =
      computeUnclaimDeviceState(device);
    device.user_id = nextUserId;
    device.claimed = claimed;
    device.caregiver_id = caregiver_id;
    await device.save();

    // Remove device_id from owner's claim_device_ids array
    const user = await User.findOne({ user_id });
    if (user) {
      const next = removeDeviceId(user.claim_device_ids, device_id);
      if (next.length !== user.claim_device_ids.length) {
        user.claim_device_ids = next;
        await user.save();
      }
    }

    // Remove device_id from the previous caregiver's caregiving_device_ids so
    // no stale caregiver link is left behind after unclaim.
    if (previousCaregiverId) {
      const caregiver = await User.findOne({ user_id: previousCaregiverId });
      if (caregiver) {
        const next = removeDeviceId(caregiver.caregiving_device_ids, device_id);
        if (next.length !== caregiver.caregiving_device_ids.length) {
          caregiver.caregiving_device_ids = next;
          await caregiver.save();
        }
      }
    }

    // Revoke any live OR pending caregiver consent grants for this device so the
    // server-authoritative relationship record matches the detached device (no
    // dangling pending invite survives an unclaim). Revoked by the owner.
    await CaregiverGrant.updateMany(
      {
        deviceId: device_id,
        status: { $in: [GRANT_STATUS.PENDING, GRANT_STATUS.ACCEPTED] },
      },
      { status: GRANT_STATUS.REVOKED, revokedAt: new Date(), revokedBy: user_id }
    );

    res.json({ status: "success", message: "Device unclaimed successfully" });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

//delete device events logic
const deleteDeviceEvents = async (req, res, next) => {
  try {
    const { device_id } = req.params;

    const device = await Device.findOne({ device_id, user_id: req.user_id });
    
    if (!device) {
      return res.status(404).json({ error: "Device not found" });
    }

    const result = await Event.deleteMany({ device_id });
    
    res.json({ 
      status: "success", 
      message: "Device events deleted successfully",
      deletedCount: result.deletedCount 
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

//delete curent caregiver acess to a device 
const deleteCaregiverAccessToDevice = async (req, res, next) => {
  try {
    const { device_id } = req.params;
    const device = await Device.findOne({ device_id, user_id: req.user_id });
    
    if (!device) {
      return res.status(404).json({ error: "Device not found or access denied" });
    }

    const caregiver_id = device.caregiver_id;
    
    // Remove caregiver from device
    device.caregiver_id = null;
    await device.save();

    // Remove device_id from caregiver's caregiving_device_ids array
    if (caregiver_id) {
      const caregiver = await User.findOne({ user_id: caregiver_id });
      if (caregiver) {
        const index = caregiver.caregiving_device_ids.indexOf(device_id);
        if (index > -1) {
          caregiver.caregiving_device_ids.splice(index, 1);
          await caregiver.save();
        }
      }

      // Revoke the server-authoritative consent grant (live or pending) so a
      // later request can no longer be authorized off a stale relationship
      // record. Revoked by the owner via the owner-only delete route.
      await CaregiverGrant.updateMany(
        {
          deviceId: device_id,
          caregiverUserId: caregiver_id,
          status: { $in: [GRANT_STATUS.PENDING, GRANT_STATUS.ACCEPTED] },
        },
        { status: GRANT_STATUS.REVOKED, revokedAt: new Date(), revokedBy: req.user_id }
      );
    }

    res.json({ status: "success", message: "Caregiver access removed successfully" });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } 
};

module.exports = {
    saveUser,
    claimDevice,
    getUserDevices,
    getADeviceEvents,
    getAllDevicesEvents,
    searchDeviceEventsByTimeRange,
    removeClaimedDevice,
    deleteDeviceEvents,
    deleteCaregiverAccessToDevice
}



