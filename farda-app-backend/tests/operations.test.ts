import { createServer, type Server } from 'node:http';
import express from 'express';
import { afterEach, describe, expect, it } from 'vitest';
import { buildInfo, createDatabaseProbe, createOperationsRouter } from '../src/operations/routes';

let server: Server | undefined;
afterEach(() => new Promise<void>(resolve => server ? server.close(() => resolve()) : resolve()));

async function start(probe: () => Promise<unknown>) {
  const app = express().use(createOperationsRouter({
    databaseProbe: probe,
    env: { BUILD_VERSION: '1.2.3', COMMIT_SHA: 'abc123', BUILD_DATE: '2026-10-17T00:00:00Z' },
    timeoutMs: 25,
  }));
  server = createServer(app).listen(0, '127.0.0.1');
  await new Promise(resolve => server!.once('listening', resolve));
  return `http://127.0.0.1:${(server.address() as { port: number }).port}`;
}

describe('operational probes', () => {
  it('keeps liveness independent and reports build provenance', async () => {
    const base = await start(async () => { throw new Error('database unavailable'); });
    const health = await fetch(`${base}/health`);
    expect(health.status).toBe(200);
    expect(await health.json()).toEqual({ status: 'ok', service: 'farda-api', build: { version: '1.2.3', commit: 'abc123', builtAt: '2026-10-17T00:00:00Z' } });
    expect((await fetch(`${base}/ready`)).status).toBe(503);
  });

  it('becomes ready only after the database probe succeeds', async () => {
    const base = await start(async () => 1);
    expect((await fetch(`${base}/ready`)).status).toBe(200);
  });

  it('does not reflect unsafe build metadata', () => {
    expect(buildInfo({ COMMIT_SHA: '<script>' }).commit).toBe('unknown');
  });

  it('coalesces unresolved readiness work instead of accumulating probes', async () => {
    let calls = 0;
    let release!: () => void;
    const base = await start(() => {
      calls += 1;
      return new Promise<void>(resolve => { release = resolve; });
    });
    const responses = await Promise.all(Array.from({ length: 8 }, () => fetch(`${base}/ready`)));
    expect(responses.every(response => response.status === 503)).toBe(true);
    expect(calls).toBe(1);
    release();
  });

  it('bounds connection, client query, and server statement time for the database probe', async () => {
    let config: ClientConfig | undefined;
    let ended = 0;
    const probe = createDatabaseProbe({
      connectionString: 'postgresql://probe:probe@localhost:5432/probe',
      timeoutMs: 1234,
      clientFactory: value => {
        config = value;
        return {
          connect: async () => {},
          query: async () => undefined,
          end: async () => { ended += 1; },
        };
      },
    });
    await probe();
    expect(config).toMatchObject({
      application_name: 'farda-readiness',
      connectionTimeoutMillis: 1234,
      query_timeout: 1234,
      statement_timeout: 1234,
    });
    expect(ended).toBe(1);
  });
});
