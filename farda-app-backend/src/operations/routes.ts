import { Router } from 'express';
import { prisma } from '../lib/prisma';

export interface BuildInfo {
  version: string;
  commit: string;
  builtAt: string;
}

type Options = {
  databaseProbe?: () => Promise<unknown>;
  env?: NodeJS.ProcessEnv;
  timeoutMs?: number;
};

const safeValue = (value: string | undefined, fallback: string) =>
  value && /^[A-Za-z0-9._:+-]{1,128}$/.test(value) ? value : fallback;

export function buildInfo(env: NodeJS.ProcessEnv = process.env): BuildInfo {
  return {
    version: safeValue(env.BUILD_VERSION, 'dev'),
    commit: safeValue(env.COMMIT_SHA, 'unknown'),
    builtAt: safeValue(env.BUILD_DATE, 'unknown'),
  };
}

async function within<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<never>((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error('readiness timeout')), timeoutMs);
        timer.unref();
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

export function createOperationsRouter(options: Options = {}) {
  const router = Router();
  const metadata = buildInfo(options.env);
  const databaseProbe = options.databaseProbe ?? (() => prisma.$queryRaw`SELECT 1`);
  const timeoutMs = options.timeoutMs ?? 3_000;

  // Liveness is process-only so an unavailable dependency does not trigger a
  // restart loop. Readiness removes an instance from service until Postgres is
  // reachable again.
  router.get('/health', (_req, res) => res.json({ status: 'ok', service: 'farda-api', build: metadata }));
  router.get('/ready', async (_req, res) => {
    try {
      await within(databaseProbe(), timeoutMs);
      return res.json({ status: 'ready', service: 'farda-api', build: metadata });
    } catch {
      return res.status(503).json({ status: 'unavailable', service: 'farda-api', build: metadata });
    }
  });
  return router;
}
