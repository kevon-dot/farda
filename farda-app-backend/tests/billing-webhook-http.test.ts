import express from 'express';
import Stripe from 'stripe';
import type { Server } from 'node:http';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
const events = vi.hoisted(() => new Set<string>());
vi.mock('../src/routes/apiRouter', () => ({ default: express.Router() }));
vi.mock('../src/lib/prisma', () => ({ prisma: { billingWebhookEvent: {
  findUnique: async ({ where }: any) => events.has(where.stripeEventId) ? { id: where.stripeEventId } : null,
  create: async ({ data }: any) => { events.add(data.stripeEventId); return data; },
} } }));
describe('production server Stripe raw-body boundary', () => {
  let server: Server; let base: string;
  const secret = 'whsec_synthetic_http_test_only';
  const stripe = new Stripe('sk_test_synthetichttponly');
  beforeAll(async () => {
    vi.stubEnv('STRIPE_BILLING_ENABLED', 'true'); vi.stubEnv('STRIPE_SECRET_KEY', 'sk_test_synthetichttponly'); vi.stubEnv('STRIPE_WEBHOOK_SECRET', secret); vi.stubEnv('STRIPE_MODE', 'test');
    vi.stubEnv('STRIPE_PRICE_PLUS_MONTHLY', 'price_plushttp'); vi.stubEnv('STRIPE_PRICE_PLUS_ANNUAL', 'price_plusannualhttp');
    vi.stubEnv('STRIPE_PRICE_FAMILY_MONTHLY', 'price_familyhttp'); vi.stubEnv('STRIPE_PRICE_FAMILY_ANNUAL', 'price_familyannualhttp');
    vi.stubEnv('FARDA_BILLING_RETURN_ORIGINS', 'https://app.test'); vi.stubEnv('FARDA_PUBLIC_BASE_URL', 'https://api.test');
    const app = (await import('../src/server')).default;
    server = await new Promise(resolve => { const s = app.listen(0, '127.0.0.1', () => resolve(s)); });
    base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  });
  afterAll(async () => { vi.unstubAllEnvs(); if (server) await new Promise<void>((resolve, reject) => server.close(e => e ? reject(e) : resolve())); });
  it('preserves signed bytes including whitespace before the JSON parser', async () => {
    const payload = '{\n  "id": "evt_raw_http", "type": "test.event", "livemode": false, "created": 1, "data": {"object": {}}\n}';
    const signature = stripe.webhooks.generateTestHeaderString({ payload, secret });
    const response = await fetch(`${base}/api/billing/webhook`, { method: 'POST', headers: { 'content-type': 'application/json', 'stripe-signature': signature }, body: payload });
    expect(response.status).toBe(200); expect(await response.json()).toEqual({ received: true }); expect(events.has('evt_raw_http')).toBe(true);
  });
  it('rejects modified bytes and unsigned requests without recording events', async () => {
    const payload = '{"id":"evt_tampered","type":"test.event","livemode":false,"created":1,"data":{"object":{}}}';
    const signature = stripe.webhooks.generateTestHeaderString({ payload, secret });
    const response = await fetch(`${base}/api/billing/webhook`, { method: 'POST', headers: { 'content-type': 'application/json', 'stripe-signature': signature }, body: `${payload} ` });
    expect(response.status).toBe(400);
    const unsigned = await fetch(`${base}/api/billing/webhook`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: payload });
    expect(unsigned.status).toBe(400); expect(events.has('evt_tampered')).toBe(false);
  });
});
