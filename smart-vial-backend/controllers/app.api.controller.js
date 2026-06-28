const Device = require("../models/Device");
const Event = require("../models/Event");
const User = require("../models/User");
const CaregiverGrant = require("../models/CaregiverGrant");
const { computeUnclaimDeviceState, removeDeviceId } = require("../utils/deviceClaim");
const { GRANT_STATUS } = require("../utils/caregiverAuthorization");
const { validateIngestionEvent } = require("../utils/eventValidation");
const DoseEvent = require("../models/DoseEvent");
const { validateDoseEventMicrostructure } = require("../utils/doseEventValidation");

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

// ============================================
// GTM-514 — user-bearer dose-event ingest relay
// ============================================
// The mobile app drains its BLE-buffered DoseLogEvents to the backend over the
// USER's better-auth session (not the per-device HMAC the firmware uses). The
// firmware ingest path authenticates the DEVICE; here the USER is authenticated
// (req.user_id, set by verifyUserToken) and must OWN the target device. Both
// paths coexist: this is an additional, separately-authenticated relay and does
// not weaken or replace controllers/ingestion.controller.js.
//
// Wire body (one event per request, matching the app):
//   { device_id, event, timestamp, sequence, idempotency_key, payload? }
//   - event: type, case-insensitive, stored uppercase
//   - timestamp: unix seconds (number)
//   - sequence: client-side buffer ordinal (preserved on the stored event)
//   - idempotency_key: client-computed stable hash for dedupe
const ingestUserDeviceEvent = async (req, res, next) => {
    try {
        const user_id = req.user_id;
        const { device_id } = req.params;
        const body = req.body || {};

        // The acting user is ALWAYS the session user — never trust a client
        // user id. We also pin the validated event to the path device_id so a
        // mismatched body.device_id can't redirect the write.
        const idempotency_key =
            typeof body.idempotency_key === "string" ? body.idempotency_key : null;
        const sequence =
            typeof body.sequence === "number" && Number.isFinite(body.sequence)
                ? body.sequence
                : null;

        // Validate the event with the shared validator (#38). Feed it the path
        // device_id and map the app's `idempotency_key` onto the validator's
        // `event_id` field so the event-type + payload checks run identically to
        // the firmware path. Malformed events are rejected with 400.
        const validation = validateIngestionEvent({
            device_id,
            event: body.event,
            timestamp: body.timestamp,
            event_id: idempotency_key === null ? undefined : idempotency_key,
            payload: body.payload,
        });
        if (!validation.ok) {
            return res.status(400).json({ error: `Bad Request: ${validation.error}` });
        }

        const { event, timestamp, payload } = validation.value;

        // Ownership: the device must exist AND be claimed by the session user.
        // This is the auth difference from the firmware HMAC path — here the
        // USER is authenticated and must own the device, else 403.
        const device = await Device.findOne({ device_id });
        if (!device) {
            return res.status(404).json({ error: "Device not found" });
        }
        if (device.user_id !== user_id) {
            return res
                .status(403)
                .json({ error: "Forbidden: device is not claimed by this user" });
        }

        // Idempotency: dedupe by the client-computed stable hash. If an Event
        // with this key already exists, return 200 deduped with no second row.
        if (idempotency_key) {
            const existing = await Event.findOne({ idempotency_key });
            if (existing) {
                return res.status(200).json({ status: "success", deduped: true });
            }
        }

        const newEvent = new Event({
            device_id,
            event_type: event,
            device_timestamp: timestamp ? new Date(timestamp * 1000) : null,
            server_timestamp: new Date(),
            payload: payload || {},
            idempotency_key,
            sequence,
            time_drift_seconds: timestamp ? Math.floor(Date.now() / 1000 - timestamp) : 0,
        });

        try {
            await newEvent.save();
        } catch (saveErr) {
            // Concurrent relay of the same buffered event: the unique index on
            // idempotency_key races us. Treat the duplicate as a successful dedupe.
            if (saveErr && saveErr.code === 11000) {
                return res.status(200).json({ status: "success", deduped: true });
            }
            throw saveErr;
        }

        // A successful user-relayed ingest is a successful sync — stamp the
        // registry field (GTM-539) so fleet-health staleness reflects app syncs.
        const now = new Date();
        device.last_seen = now;
        device.last_sync_at = now;
        await device.save();

        return res.status(200).json({
            status: "success",
            deduped: false,
            event: {
                device_id: newEvent.device_id,
                event_type: newEvent.event_type,
                idempotency_key: newEvent.idempotency_key,
                sequence: newEvent.sequence,
                device_timestamp: newEvent.device_timestamp,
                server_timestamp: newEvent.server_timestamp,
            },
        });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
};

// ============================================
// GTM-519 — Dose-event microstructure capture (server-authoritative)
// ============================================
// Records ONE full dose interaction's lifecycle as a typed, ordered,
// tokenization-ready, condition-agnostic DoseEvent. This is the canonical,
// server-authoritative record built on top of the same user-bearer relay used
// by GTM-514: the acting subject is the SESSION user (req.user_id), the device
// is bound from the path param and must be OWNED by that user (IDOR-guarded), the
// server assigns stage ordering + the canonical recordedAt (client ordering is
// never trusted), and malformed / out-of-order / incomplete / PHI-bearing
// sequences are rejected by the shared validator (defense-in-depth: the model
// re-validates on save).
//
// Audit: a PHI-FREE structured line is emitted (subject + device by id, stage
// count, schema version, idempotency key) — never any payload or patient data.
// The persisted DoseEvent (ids/codes/numbers only) is itself the durable trail.
//
// Wire body:
//   { client_dose_id, idempotency_key, stages: [{ type, timestamp, payload? }] }
const ingestDoseEventMicrostructure = async (req, res, next) => {
    try {
        const user_id = req.user_id;
        const { device_id } = req.params;
        const body = req.body || {};

        // 1. Validate + server-authoritatively normalize the microstructure:
        //    strict per-stage payloads, no-PHI guard, completeness, and ordering
        //    are all decided here from device timestamps — not the client array.
        const validation = validateDoseEventMicrostructure({
            client_dose_id: body.client_dose_id,
            idempotency_key: body.idempotency_key,
            stages: Array.isArray(body.stages) ? body.stages : body.stages,
        });
        if (!validation.ok) {
            return res.status(400).json({ error: `Bad Request: ${validation.error}` });
        }
        const normalized = validation.value;

        // 2. Ownership (IDOR guard): the device must exist AND be claimed by the
        //    session user. device_id is the path param, never a client-asserted
        //    body field, so the write can't be redirected to another subject.
        const device = await Device.findOne({ device_id });
        if (!device) {
            return res.status(404).json({ error: "Device not found" });
        }
        if (device.user_id !== user_id) {
            return res
                .status(403)
                .json({ error: "Forbidden: device is not claimed by this user" });
        }

        // 3. Idempotency: dedupe by the client-computed stable key.
        if (normalized.idempotency_key) {
            const existing = await DoseEvent.findOne({
                idempotency_key: normalized.idempotency_key,
            });
            if (existing) {
                return res.status(200).json({ status: "success", deduped: true });
            }
        }

        // 4. Persist. The SERVER sets recordedAt (canonical time) and binds the
        //    subject ids; stage order/tokens come from the validator. The model
        //    pre-validate hook re-runs the full check as defense-in-depth.
        const doseEvent = new DoseEvent({
            device_id,
            user_id,
            client_dose_id: normalized.client_dose_id,
            idempotency_key: normalized.idempotency_key,
            schema_version: normalized.schema_version,
            stages: normalized.stages,
            token_sequence: normalized.token_sequence,
            recordedAt: new Date(),
        });

        try {
            await doseEvent.save();
        } catch (saveErr) {
            // Concurrent relay of the same dose: the unique idempotency_key index
            // races us. Treat the duplicate as a successful dedupe.
            if (saveErr && saveErr.code === 11000) {
                return res.status(200).json({ status: "success", deduped: true });
            }
            throw saveErr;
        }

        // A successful capture is a successful sync — stamp the registry fields
        // (GTM-539) so fleet-health staleness reflects app dose syncs.
        const now = new Date();
        device.last_seen = now;
        device.last_sync_at = now;
        await device.save();

        // PHI-free audit line: ids + counts + version only, never any payload.
        console.log("DoseEvent microstructure recorded", {
            user_id,
            device_id,
            idempotency_key: normalized.idempotency_key,
            schema_version: normalized.schema_version,
            stage_count: normalized.stages.length,
        });

        return res.status(201).json({
            status: "success",
            deduped: false,
            dose_event: {
                id: doseEvent._id,
                device_id: doseEvent.device_id,
                schema_version: doseEvent.schema_version,
                recordedAt: doseEvent.recordedAt,
                token_sequence: doseEvent.token_sequence,
            },
        });
    } catch (err) {
        return res.status(500).json({ error: err.message });
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
    deleteCaregiverAccessToDevice,
    ingestUserDeviceEvent,
    ingestDoseEventMicrostructure
}



