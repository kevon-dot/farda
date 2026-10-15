const express = require('express');
const cors = require('cors');
const mongoose = require('mongoose');
const config = require('./config/config');
const connectDB = require('./config/databaseConfig');
const { requestLimit } = require('./middleware/requestLimit');
const { checkSessionStore, closePool } = require('./middleware/verifyUserToken');

function createApp() {
  const app = express();
  app.disable('x-powered-by');
  // Proxy trust must be deliberately configured at the gateway, never accepted
  // from arbitrary X-Forwarded-For headers in this service.
  app.set('trust proxy', false);
  app.use(cors({ origin: config.corsOrigins, credentials: false }));
  app.use(requestLimit({ max: 180, windowMs: 60000 }));
  app.use(express.json({ limit: '16kb', strict: true }));
  app.get('/health', (_req, res) => res.json({ status: 'ok', contract: 'vial-observations-v1' }));
  app.use('/api/ingest', require('./routes/ingestionAPI'));
  app.use('/api/caregiver', require('./routes/caregiverAPI'));
  app.use('/api/user', require('./routes/userAPI'));
  app.use((_req, res) => res.status(404).json({ error: 'Route not found' }));
  app.use((error, _req, res, _next) => {
    if (error.type === 'entity.too.large') return res.status(413).json({ error: 'Request exceeds 16 KiB', code: 'request_too_large' });
    if (error instanceof SyntaxError) return res.status(400).json({ error: 'Invalid JSON', code: 'invalid_json' });
    return res.status(503).json({ error: 'Service temporarily unavailable', code: 'service_unavailable' });
  });
  return app;
}

async function start() {
  config.validateConfig(config);
  await connectDB(config.mongoUri);
  await checkSessionStore();
  const server = createApp().listen(config.port, () => console.info('Vial API ready'));
  const stop = () => server.close(async () => { await closePool(); await mongoose.disconnect(); });
  process.once('SIGTERM', stop);
  process.once('SIGINT', stop);
  return server;
}

if (require.main === module) {
  start().catch(async () => {
    console.error('Vial API startup failed: verify database configuration, schema, indexes and replica-set support.');
    await closePool().catch(() => {});
    await mongoose.disconnect().catch(() => {});
    process.exitCode = 1;
  });
}

module.exports = { createApp, start };
