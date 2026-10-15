const mongoose = require('mongoose');
const Device = require('../models/Device');
const Event = require('../models/Event');
const User = require('../models/User');

async function connectDB(uri) {
  await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000, autoIndex: false });
  const hello = await mongoose.connection.db.admin().command({ hello: 1 });
  if (!hello.setName && hello.msg !== 'isdbgrid') throw new Error('MongoDB transactions require a replica set or sharded deployment');
  // Readiness requires the real unique indexes. Never syncIndexes/drop existing
  // indexes or backfill legacy owners automatically during startup.
  await Device.createIndexes();
  await Event.createIndexes();
  await User.createIndexes();
  return mongoose.connection;
}

module.exports = connectDB;
