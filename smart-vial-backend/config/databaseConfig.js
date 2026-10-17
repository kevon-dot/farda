const mongoose = require('mongoose');
const Device = require('../models/Device');
const Event = require('../models/Event');
const User = require('../models/User');

async function connectDB(uri) {
  await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000, autoIndex: false, autoCreate: false });
  return mongoose.connection;
}

async function prepareDatabase(uri, {
  connect = connectDB,
  connection = mongoose.connection,
  models = [Device, Event, User],
} = {}) {
  await connect(uri);
  const hello = await connection.db.admin().command({ hello: 1 });
  if (!hello.setName && hello.msg !== 'isdbgrid') throw new Error('MongoDB transactions require a replica set or sharded deployment');
  // The release job owns schema/index privileges. Runtime startup deliberately
  // does not create collections or indexes and can use a read/write-only role.
  for (const model of models) await model.createIndexes();
  return connection;
}

module.exports = connectDB;
module.exports.prepareDatabase = prepareDatabase;
