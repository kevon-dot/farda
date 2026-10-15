const mongoose = require('mongoose');
const { EVENT_TYPES } = require('../lib/validation');

const EventSchema = new mongoose.Schema({
  event_id: { type: String, required: true, immutable: true },
  device_id: { type: String, required: true, immutable: true },
  ownership_epoch: { type: String, required: true, immutable: true },
  owner_id: { type: String, required: true, immutable: true },
  boot_id: { type: String, required: true, immutable: true },
  sequence: { type: Number, required: true, min: 0, immutable: true },
  event_type: { type: String, required: true, enum: EVENT_TYPES, immutable: true },
  payload: { type: mongoose.Schema.Types.Mixed, required: true, immutable: true },
  source: { type: String, required: true, enum: ['device_credential', 'phone_ble'], immutable: true },
  evidence_type: { type: String, enum: ['vial_observation'], default: 'vial_observation', immutable: true },
  device_timestamp: { type: Date, required: true, immutable: true },
  server_timestamp: { type: Date, required: true, immutable: true },
  content_hash: { type: String, required: true, immutable: true, select: false },
  time_drift_seconds: { type: Number, required: true, immutable: true },
}, { versionKey: false, autoIndex: false });

// Partial filters leave legacy, unowned events quarantined. Never backfill their
// owner from the current device owner; that would leak a former owner's history.
EventSchema.index({ device_id: 1, ownership_epoch: 1, event_id: 1 }, {
  unique: true, name: 'observation_event_identity',
  partialFilterExpression: { ownership_epoch: { $type: 'string' }, event_id: { $type: 'string' } },
});
EventSchema.index({ device_id: 1, ownership_epoch: 1, boot_id: 1, sequence: 1 }, {
  unique: true, name: 'observation_sequence_identity',
  partialFilterExpression: { ownership_epoch: { $type: 'string' }, boot_id: { $type: 'string' }, sequence: { $type: 'number' } },
});
EventSchema.index({ owner_id: 1, server_timestamp: -1 });
EventSchema.index({ device_id: 1, ownership_epoch: 1, server_timestamp: -1 });

EventSchema.pre('save', function() {
  if (!this.isNew) throw new Error('Observations are append-only');
});
for (const operation of ['updateOne', 'updateMany', 'findOneAndUpdate', 'replaceOne', 'findOneAndReplace', 'deleteMany', 'findOneAndDelete']) {
  EventSchema.pre(operation, function() { throw new Error('Observations are append-only'); });
}
EventSchema.pre('deleteOne', { document: true, query: true }, function() { throw new Error('Observations are append-only'); });
EventSchema.pre('bulkWrite', function() { throw new Error('Use the validated observation ingestion path'); });

module.exports = mongoose.model('Event', EventSchema);
