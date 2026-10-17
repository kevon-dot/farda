const test = require('node:test');
const assert = require('node:assert/strict');
const net = require('node:net');
const { createRuntimeDependencies, start } = require('../Server');
const { prepareDatabase } = require('../config/databaseConfig');

async function unusedPort() {
  const listener = net.createServer().listen(0, '127.0.0.1');
  await new Promise(resolve => listener.once('listening', resolve));
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  return port;
}

test('runtime listens for liveness while dependencies are unavailable', async t => {
  const port = await unusedPort();
  const dependencies = { readiness: async () => { throw new Error('unavailable'); }, close: async () => {} };
  const server = await start({
    runtimeConfig: { port, mongoUri: 'mongodb://localhost/farda', databaseUrl: 'postgresql://localhost/farda' },
    dependencies,
    installSignalHandlers: false,
    onDependencyError: () => {},
  });
  await new Promise(resolve => server.once('listening', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  assert.equal((await fetch(`http://127.0.0.1:${port}/health`)).status, 200);
  assert.equal((await fetch(`http://127.0.0.1:${port}/ready`)).status, 503);
});

test('runtime Mongo connection retries are single-flight and recoverable', async () => {
  let ready = false;
  let attempts = 0;
  const dependencies = createRuntimeDependencies({
    mongoUri: 'mongodb://localhost/farda',
    mongoReady: () => ready,
    connectMongo: async () => {
      attempts += 1;
      if (attempts === 1) throw new Error('offline');
      ready = true;
    },
    postgresReady: async () => {},
    close: async () => {},
  });
  await assert.rejects(Promise.all([dependencies.readiness(), dependencies.readiness()]), /offline/);
  assert.equal(attempts, 1);
  await dependencies.readiness();
  assert.equal(attempts, 2);
});

test('only the preparation job creates MongoDB indexes', async () => {
  const calls = [];
  const connection = { db: { admin: () => ({ command: async () => ({ setName: 'rs0' }) }) } };
  await prepareDatabase('mongodb://prepare/farda', {
    connect: async uri => { calls.push(['connect', uri]); },
    connection,
    models: [
      { createIndexes: async () => { calls.push(['index', 'Device']); } },
      { createIndexes: async () => { calls.push(['index', 'Event']); } },
    ],
  });
  assert.deepEqual(calls, [
    ['connect', 'mongodb://prepare/farda'],
    ['index', 'Device'],
    ['index', 'Event'],
  ]);
});
