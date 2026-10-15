const path = require('node:path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env'), quiet: true });

function readConfig(env = process.env) {
  return {
    port: Number(env.PORT || 5000),
    nodeEnv: env.NODE_ENV || 'development',
    mongoUri: env.MONGODB_URI || env.MONGO_URI,
    databaseUrl: env.DATABASE_URL,
    corsOrigins: (env.CORS_ORIGINS || '').split(',').map(value => value.trim()).filter(Boolean),
    // No fleet key, JWT fallback or automatic provisioning is supported.
  };
}

function validateConfig(config) {
  const missing = ['mongoUri', 'databaseUrl'].filter(key => !config[key]);
  if (missing.length) throw new Error('Missing required configuration: ' + missing.join(', '));
  if (!/^mongodb(?:\+srv)?:\/\//.test(config.mongoUri)) throw new Error('Invalid MongoDB connection configuration');
  if (!/^postgres(?:ql)?:\/\//.test(config.databaseUrl)) throw new Error('Invalid PostgreSQL connection configuration');
  if (!Number.isInteger(config.port) || config.port < 1 || config.port > 65535) throw new Error('Invalid PORT');
  return config;
}

module.exports = { ...readConfig(), readConfig, validateConfig };
