const { Router } = require('express');

function safeValue(value, fallback) {
  return typeof value === 'string' && /^[A-Za-z0-9._:+-]{1,128}$/.test(value) ? value : fallback;
}

function buildInfo(env = process.env) {
  return {
    version: safeValue(env.BUILD_VERSION, 'dev'),
    commit: safeValue(env.COMMIT_SHA, 'unknown'),
    builtAt: safeValue(env.BUILD_DATE, 'unknown'),
  };
}

async function within(promise, timeoutMs) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error('readiness timeout')), timeoutMs);
        timer.unref();
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

function createOperationsRouter({ readinessProbe = async () => {}, env = process.env, timeoutMs = 3000 } = {}) {
  const router = Router();
  const metadata = buildInfo(env);
  router.get('/health', (_req, res) => res.json({ status: 'ok', service: 'smart-vial-api', contract: 'vial-observations-v1', build: metadata }));
  router.get('/ready', async (_req, res) => {
    try {
      await within(readinessProbe(), timeoutMs);
      return res.json({ status: 'ready', service: 'smart-vial-api', build: metadata });
    } catch {
      return res.status(503).json({ status: 'unavailable', service: 'smart-vial-api', build: metadata });
    }
  });
  return router;
}

module.exports = { buildInfo, createOperationsRouter };
