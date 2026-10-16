import { describe, expect, it, vi } from 'vitest';
import type Stripe from 'stripe';
import { inspectPhotonRemote, inspectRuntime, inspectStripeRemote, stripeWebhookEvents } from '../scripts/runtime-readiness';

const configured = {
  STRIPE_MODE: 'test', STRIPE_SECRET_KEY: 'rk_test_redacted', STRIPE_WEBHOOK_SECRET: 'whsec_redacted',
  STRIPE_PRICE_PLUS_MONTHLY: 'price_pm', STRIPE_PRICE_PLUS_ANNUAL: 'price_pa',
  STRIPE_PRICE_FAMILY_MONTHLY: 'price_fm', STRIPE_PRICE_FAMILY_ANNUAL: 'price_fa',
  FARDA_BILLING_RETURN_ORIGINS: 'https://app.farda.test', FARDA_PUBLIC_BASE_URL: 'https://api.farda.test',
  STRIPE_BILLING_ENABLED: 'false', FARDA_REFILL_PROVIDER_ENVIRONMENT: 'sandbox',
  PHOTON_CLIENT_ID: 'present', PHOTON_CLIENT_SECRET: 'present', FARDA_REFILL_PROVIDER_ENABLED: 'false',
};

describe('runtime readiness', () => {
  it('accepts complete disabled configuration without exposing values', () => {
    const results = inspectRuntime(configured);
    expect(results.every(result => result.status === 'pass')).toBe(true);
    expect(JSON.stringify(results)).not.toContain('rk_test_redacted');
    expect(JSON.stringify(results)).not.toContain('whsec_redacted');
    expect(JSON.stringify(results)).not.toContain('"present"');
  });

  it('blocks placeholder hosts and reports missing provider configuration', () => {
    const results = inspectRuntime({ STRIPE_MODE: 'test', FARDA_PUBLIC_BASE_URL: 'https://your-host.example.com' });
    expect(results.find(result => result.name === 'webhook.public_url')?.status).toBe('blocked');
    expect(results.find(result => result.name === 'photon.client_secret')?.status).toBe('fail');
  });

  it('read-backs prices, portal, and the exact webhook event set', async () => {
    const lookup: Record<string, string> = { price_pm: 'farda_plus_monthly_usd', price_pa: 'farda_plus_annual_usd', price_fm: 'farda_family_monthly_usd', price_fa: 'farda_family_annual_usd' };
    const retrieve = vi.fn(async (id: string) => ({ id, active: true, livemode: false, currency: 'usd', lookup_key: lookup[id], unit_amount: id.endsWith('pm') ? 1499 : id.endsWith('pa') ? 14999 : id.endsWith('fm') ? 2499 : 24999, type: 'recurring', recurring: { interval: id.endsWith('m') ? 'month' : 'year', interval_count: 1 }, product: { active: true, deleted: false, livemode: false, metadata: { farda_catalog_key: id.startsWith('price_p') ? 'plus' : 'family' } } }));
    const stripe = { prices: { retrieve }, billingPortal: { configurations: { list: vi.fn(async () => ({ data: [{ id: 'bpc_test', is_default: true, livemode: false, features: { invoice_history: { enabled: true }, payment_method_update: { enabled: true }, subscription_cancel: { enabled: true, mode: 'at_period_end', proration_behavior: 'none' }, subscription_update: { enabled: false } } }] })) } }, webhookEndpoints: { list: vi.fn(async () => ({ data: [{ url: 'https://api.farda.test/api/billing/webhook', status: 'enabled', livemode: false, enabled_events: [...stripeWebhookEvents] }] })) } } as unknown as Stripe;
    const results = await inspectStripeRemote(configured, stripe);
    expect(results.every(result => result.status === 'pass')).toBe(true);
    expect(retrieve).toHaveBeenCalledTimes(4);
  });

  it('checks Photon authentication without sending a clinical API request', async () => {
    const fetcher = vi.fn(async () => new Response(JSON.stringify({ access_token: 'not-reported', token_type: 'Bearer' }), { status: 200, headers: { 'content-type': 'application/json' } }));
    const results = await inspectPhotonRemote(configured, fetcher as typeof fetch);
    expect(results).toEqual([{ name: 'photon.remote_auth', status: 'pass', detail: 'credentials accepted; no patient data read and no order submitted' }]);
    expect(fetcher).toHaveBeenCalledOnce();
    expect(fetcher.mock.calls[0][0]).toBe('https://auth.neutron.health/oauth/token');
  });

  it.each(['https://127.0.0.1', 'https://10.1.2.3', 'https://172.16.2.3', 'https://192.168.2.3', 'https://[::1]', 'https://[fd00::1]', 'https://[::ffff:10.1.2.3]', 'https://api.farda.test/path', 'https://api.farda.test/?query=1', 'https://api.farda.test/#fragment'])('rejects non-public or non-origin webhook base %s', base => {
    const results = inspectRuntime({ ...configured, FARDA_PUBLIC_BASE_URL: base });
    expect(results.find(result => result.name === 'webhook.public_url')?.status).toBe('blocked');
  });

  it('refuses malformed Stripe mode and key before making remote calls', async () => {
    const retrieve = vi.fn();
    const stripe = { prices: { retrieve } } as unknown as Stripe;
    await expect(inspectStripeRemote({ ...configured, STRIPE_MODE: 'unknown' }, stripe)).resolves.toMatchObject([{ status: 'blocked' }]);
    await expect(inspectStripeRemote({ ...configured, STRIPE_SECRET_KEY: 'rk_live_wrong_mode' }, stripe)).resolves.toMatchObject([{ status: 'blocked' }]);
    expect(retrieve).not.toHaveBeenCalled();
  });

  it('requires portal cancellation policy and webhook mode to match', async () => {
    const product = { active: true, deleted: false, livemode: false, metadata: { farda_catalog_key: 'plus' } };
    const stripe = { prices: { retrieve: vi.fn(async (id: string) => ({ active: true, livemode: false, currency: 'usd', lookup_key: id.endsWith('pm') ? 'farda_plus_monthly_usd' : id.endsWith('pa') ? 'farda_plus_annual_usd' : id.endsWith('fm') ? 'farda_family_monthly_usd' : 'farda_family_annual_usd', unit_amount: id.endsWith('pm') ? 1499 : id.endsWith('pa') ? 14999 : id.endsWith('fm') ? 2499 : 24999, type: 'recurring', recurring: { interval: id.endsWith('m') ? 'month' : 'year', interval_count: 1 }, product: id.startsWith('price_p') ? product : { ...product, metadata: { farda_catalog_key: 'family' } } })) }, billingPortal: { configurations: { list: vi.fn(async () => ({ data: [{ is_default: true, livemode: false, features: { invoice_history: { enabled: true }, payment_method_update: { enabled: true }, subscription_cancel: { enabled: true, mode: 'immediately', proration_behavior: 'create_prorations' }, subscription_update: { enabled: false } } }] })) } }, webhookEndpoints: { list: vi.fn(async () => ({ data: [{ url: 'https://api.farda.test/api/billing/webhook', status: 'enabled', livemode: true, enabled_events: [...stripeWebhookEvents] }] })) } } as unknown as Stripe;
    const results = await inspectStripeRemote(configured, stripe);
    expect(results.find(result => result.name === 'stripe.customer_portal')?.status).toBe('fail');
    expect(results.find(result => result.name === 'stripe.webhook_endpoint')?.status).toBe('fail');
  });

  it('refuses malformed Photon environment before authentication', async () => {
    const fetcher = vi.fn();
    await expect(inspectPhotonRemote({ ...configured, FARDA_REFILL_PROVIDER_ENVIRONMENT: 'typo' }, fetcher as typeof fetch)).resolves.toMatchObject([{ status: 'blocked' }]);
    expect(fetcher).not.toHaveBeenCalled();
  });
});
