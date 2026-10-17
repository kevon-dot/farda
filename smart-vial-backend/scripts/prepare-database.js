const mongoose = require('mongoose');
const config = require('../config/config');
const connectDB = require('../config/databaseConfig');
const { checkSessionStore, closePool } = require('../middleware/verifyUserToken');

async function prepare() {
  config.validateConfig(config);
  await connectDB(config.mongoUri);
  await checkSessionStore();
  console.info('Vial database checks and indexes completed.');
}

prepare()
  .catch(() => {
    console.error('Vial database preparation failed: verify database configuration, indexes and replica-set support.');
    process.exitCode = 1;
  })
  .finally(async () => {
    await closePool().catch(() => {});
    await mongoose.disconnect().catch(() => {});
  });
