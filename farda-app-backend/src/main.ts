import logger from 'jet-logger';
import env from './common/constants/env';
import app from './server';
import { prisma } from './lib/prisma';
import { reminderService } from './reminders/routes';
import { startReminderWorker } from './reminders/service';
import { circleAlertService } from './circle/routes';

if (env.NODE_ENV === 'production') {
  if (!env.DATABASE_URL || !process.env.BETTER_AUTH_SECRET || process.env.BETTER_AUTH_SECRET.length < 32) throw new Error('Production requires DATABASE_URL and a strong BETTER_AUTH_SECRET');
  if (!process.env.BETTER_AUTH_URL?.startsWith('https://')) throw new Error('Production requires an HTTPS BETTER_AUTH_URL');
}

// Each optional channel worker returns a stop/drain function. Native APNs can
// join this lifecycle without adding a second process-level signal handler.
const stopWorkers: Array<() => void | Promise<void>> = [];
const backgroundTasks: Array<() => Promise<void>> = [
  () => reminderService.tick().then(() => undefined),
  () => circleAlertService.materialize(100).then(() => undefined),
];
export const httpServer = app.listen(env.PORT, env.HOST, error => {
  if (error || shutdownPromise) return;
  logger.info(`Express server started on ${env.HOST}:${env.PORT}`);
  stopWorkers.push(startReminderWorker({ tick: async () => {
    for (const run of backgroundTasks) await run();
  } }));
});

let shutdownPromise: Promise<void> | undefined;
export function shutdown(): Promise<void> {
  if (shutdownPromise) return shutdownPromise;
  shutdownPromise = (async () => {
    const forceExit = setTimeout(() => process.exit(1), 30_000);
    forceExit.unref();
    try {
      // Stop accepting new requests immediately; let current requests and any
      // already-started dispatch finish their durable commit before closing PG.
      const httpClosed = new Promise<void>(resolve => httpServer.close(() => resolve()));
      const workerResults = await Promise.allSettled(stopWorkers.map(stop => Promise.resolve(stop())));
      await httpClosed;
      await prisma.$disconnect();
      if (workerResults.some(result => result.status === 'rejected')) process.exitCode = 1;
    } finally { clearTimeout(forceExit); }
  })();
  return shutdownPromise;
}
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.once(signal, () => {
  void shutdown().catch(() => { process.exitCode = 1; logger.err('shutdown_failed'); });
});
httpServer.once('error', () => {
  process.exitCode = 1;
  logger.err('server_start_failed');
  void shutdown().catch(() => { logger.err('shutdown_failed'); });
});
