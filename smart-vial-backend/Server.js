const express = require('express');
const cors = require('cors');
const mongoose = require('mongoose');
const config = require('./config/config');
const connectDB = require('./config/databaseConfig');
const { requestLimit } = require('./middleware/requestLimit');
const { checkSessionStore, closePool } = require('./middleware/verifyUserToken');
const { createOperationsRouter, buildInfo } = require('./lib/operations');

function createRuntimeDependencies({
  mongoUri = config.mongoUri,
  connectMongo = connectDB,
  mongoReady = () => mongoose.connection.readyState === 1,
  postgresReady = checkSessionStore,
  close = async () => { await closePool(); await mongoose.disconnect(); },
} = {}) {
  let mongoConnect;
  let dependencyCheck;
  async function ensureMongo() {
    if (mongoReady()) return;
    mongoConnect ||= Promise.resolve()
      .then(() => connectMongo(mongoUri))
      .finally(() => { mongoConnect = undefined; });
    await mongoConnect;
    if (!mongoReady()) throw new Error('MongoDB is not connected');
  }
  return {
    readiness: () => {
      dependencyCheck ||= Promise.resolve()
        .then(async () => {
          await ensureMongo();
          await postgresReady();
        })
        .finally(() => { dependencyCheck = undefined; });
      return dependencyCheck;
    },
    close,
  };
}

function createApp({ readinessProbe } = {}) {
  const app = express();
  app.disable('x-powered-by');
  // Proxy trust must be deliberately configured at the gateway, never accepted
  // from arbitrary X-Forwarded-For headers in this service.
  app.set('trust proxy', false);
  app.use(cors({ origin: config.corsOrigins, credentials: false }));
  app.use(requestLimit({ max: 180, windowMs: 60000 }));
  app.use(express.json({ limit: '16kb', strict: true }));
  app.use(createOperationsRouter({
    readinessProbe: readinessProbe || (async () => {
      if (mongoose.connection.readyState !== 1) throw new Error('MongoDB is not connected');
      await checkSessionStore();
    }),
  }));
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

async function start({
  runtimeConfig = config,
  dependencies = createRuntimeDependencies({ mongoUri: runtimeConfig.mongoUri }),
  installSignalHandlers = true,
  onDependencyError = () => console.error('Vial API dependencies unavailable; readiness remains closed.'),
} = {}) {
  config.validateConfig(runtimeConfig);
  const server = createApp({ readinessProbe: dependencies.readiness }).listen(runtimeConfig.port, () => {
    const build = buildInfo();
    console.info(`Vial API listening (version=${build.version} commit=${build.commit})`);
  });
  // Warm connections without making process liveness depend on datastore
  // availability. Each readiness request can retry a failed initial connect.
  void dependencies.readiness().catch(onDependencyError);
  let stopPromise;
  const stop = () => {
    stopPromise ||= new Promise(resolve => server.close(async () => {
      await dependencies.close();
      resolve();
    }));
    return stopPromise;
  };
  if (installSignalHandlers) {
    process.once('SIGTERM', () => { void stop(); });
    process.once('SIGINT', () => { void stop(); });
  }
  return server;
}

async function run() {
  try {
    await start();
  } catch {
    console.error('Vial API startup failed: verify database configuration, schema, indexes and replica-set support.');
    await closePool().catch(() => {});
    await mongoose.disconnect().catch(() => {});
    process.exitCode = 1;
  }
}

if (require.main === module) {
  void run();
}

module.exports = { createApp, createRuntimeDependencies, start, run };
