import Stripe from 'stripe';
import { isIP } from 'node:net';
import { priceCatalog } from '../src/billing/catalog';

export type RuntimeEnvironment = Record<string, string | undefined>;
export type Check = { name: string; status: 'pass' | 'fail' | 'blocked'; detail: string };

export const stripeWebhookEvents = [
  'customer.subscription.created', 'customer.subscription.updated', 'customer.subscription.deleted',
  'invoice.paid', 'invoice.payment_failed', 'checkout.session.completed',
  'checkout.session.async_payment_succeeded', 'checkout.session.async_payment_failed',
] as const;
const stripeLookupKeys: Record<keyof typeof priceCatalog, string> = {
  plus_monthly: 'farda_plus_monthly_usd', plus_annual: 'farda_plus_annual_usd',
  family_monthly: 'farda_family_monthly_usd', family_annual: 'farda_family_annual_usd',
};

const configured = (value?: string) => Boolean(value?.trim());
const isPlaceholder = (value: string) => /example\.(com|org|net)|your-host|localhost|127\.0\.0\.1/i.test(value);

function publicHttpsUrl(value?: string): URL | undefined {
  if (!value) return undefined;
  try {
    const url = new URL(value);
    const hostname = url.hostname.replace(/^\[|\]$/g, '').toLowerCase();
    const ipv4Private = (address: string) => {
      const octets = address.split('.').map(Number);
      return octets[0] === 0 || octets[0] === 10 || octets[0] === 127 ||
        (octets[0] === 100 && octets[1] >= 64 && octets[1] <= 127) ||
        (octets[0] === 169 && octets[1] === 254) ||
        (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) ||
        (octets[0] === 192 && octets[1] === 168) ||
        (octets[0] === 198 && (octets[1] === 18 || octets[1] === 19));
    };
    const mappedIpv4 = (address: string) => {
      if (!address.startsWith('::ffff:')) return undefined;
      const suffix = address.slice(7);
      if (isIP(suffix) === 4) return suffix;
      const groups = suffix.split(':');
      if (groups.length !== 2 || groups.some(group => !/^[0-9a-f]{1,4}$/.test(group))) return undefined;
      const values = groups.map(group => Number.parseInt(group, 16));
      return `${values[0] >> 8}.${values[0] & 255}.${values[1] >> 8}.${values[1] & 255}`;
    };
    const mapped = mappedIpv4(hostname);
    const ipv6Private = hostname === '::' || hostname === '::1' || /^(fc|fd)/.test(hostname) || /^fe[89ab]/.test(hostname) ||
      (mapped !== undefined && ipv4Private(mapped));
    const privateAddress = isIP(hostname) === 4 ? ipv4Private(hostname) : isIP(hostname) === 6 && ipv6Private;
    const exactOrigin = url.href === `${url.origin}/`;
    return url.protocol === 'https:' && !url.username && !url.password && !isPlaceholder(hostname) && !privateAddress && exactOrigin ? url : undefined;
  } catch { return undefined; }
}

export function inspectRuntime(env: RuntimeEnvironment): Check[] {
  const checks: Check[] = [];
  const mode = env.STRIPE_MODE;
  checks.push({ name: 'stripe.mode', status: mode === 'test' || mode === 'live' ? 'pass' : 'fail', detail: mode === 'test' || mode === 'live' ? `${mode} mode selected` : 'STRIPE_MODE must be test or live' });
  const expectedKeyPrefix = mode === 'live' ? /^(sk|rk)_live_/ : /^(sk|rk)_test_/;
  checks.push({ name: 'stripe.secret_key', status: configured(env.STRIPE_SECRET_KEY) && expectedKeyPrefix.test(env.STRIPE_SECRET_KEY!) ? 'pass' : 'fail', detail: configured(env.STRIPE_SECRET_KEY) ? 'present; mode prefix checked' : 'STRIPE_SECRET_KEY is missing' });
  checks.push({ name: 'stripe.webhook_secret', status: /^whsec_.+/.test(env.STRIPE_WEBHOOK_SECRET ?? '') ? 'pass' : 'fail', detail: configured(env.STRIPE_WEBHOOK_SECRET) ? 'present; format checked' : 'STRIPE_WEBHOOK_SECRET is missing' });

  for (const [key, definition] of Object.entries(priceCatalog)) {
    const value = env[definition.env];
    checks.push({ name: `stripe.price.${key}`, status: /^price_[A-Za-z0-9]+$/.test(value ?? '') ? 'pass' : 'fail', detail: configured(value) ? `${definition.env} has a Price ID` : `${definition.env} is missing` });
  }

  const origins = (env.FARDA_BILLING_RETURN_ORIGINS ?? '').split(',').map(value => value.trim()).filter(Boolean);
  const validOrigins = origins.length > 0 && origins.every(value => {
    const url = publicHttpsUrl(value);
    return url?.origin === value && url.pathname === '/';
  });
  checks.push({ name: 'stripe.return_origins', status: validOrigins ? 'pass' : 'fail', detail: validOrigins ? `${origins.length} exact HTTPS origin(s) configured` : 'FARDA_BILLING_RETURN_ORIGINS needs exact, non-placeholder HTTPS origins' });

  const base = publicHttpsUrl(env.FARDA_PUBLIC_BASE_URL);
  checks.push({ name: 'webhook.public_url', status: base ? 'pass' : 'blocked', detail: base ? `expected endpoint ${new URL('/api/billing/webhook', base).href}` : 'FARDA_PUBLIC_BASE_URL is not a confirmed public HTTPS URL' });

  const photonEnvironment = env.FARDA_REFILL_PROVIDER_ENVIRONMENT;
  checks.push({ name: 'photon.environment', status: photonEnvironment === 'sandbox' || photonEnvironment === 'production' ? 'pass' : 'fail', detail: photonEnvironment === 'sandbox' || photonEnvironment === 'production' ? `${photonEnvironment} selected` : 'FARDA_REFILL_PROVIDER_ENVIRONMENT must be sandbox or production' });
  for (const key of ['PHOTON_CLIENT_ID', 'PHOTON_CLIENT_SECRET'] as const) {
    checks.push({ name: `photon.${key === 'PHOTON_CLIENT_ID' ? 'client_id' : 'client_secret'}`, status: configured(env[key]) ? 'pass' : 'fail', detail: configured(env[key]) ? `${key} is present` : `${key} is missing` });
  }

  const stripeEnabled = env.STRIPE_BILLING_ENABLED === 'true';
  const photonEnabled = env.FARDA_REFILL_PROVIDER_ENABLED === 'true';
  checks.push({ name: 'stripe.enablement', status: 'pass', detail: stripeEnabled ? 'enabled; configuration and end-to-end evidence remain authoritative' : 'disabled (safe default)' });
  checks.push({ name: 'photon.enablement', status: 'pass', detail: photonEnabled ? 'enabled; verified links and sandbox evidence remain authoritative' : 'disabled (safe default)' });
  return checks;
}

export async function inspectStripeRemote(env: RuntimeEnvironment, stripe?: Stripe): Promise<Check[]> {
  if (env.STRIPE_MODE !== 'test' && env.STRIPE_MODE !== 'live') return [{ name: 'stripe.remote', status: 'blocked', detail: 'STRIPE_MODE must be test or live before remote verification' }];
  const expectedPrefix = env.STRIPE_MODE === 'live' ? /^(sk|rk)_live_/ : /^(sk|rk)_test_/;
  if (!configured(env.STRIPE_SECRET_KEY) || !expectedPrefix.test(env.STRIPE_SECRET_KEY!)) return [{ name: 'stripe.remote', status: 'blocked', detail: 'STRIPE_SECRET_KEY is missing or does not match STRIPE_MODE' }];
  const api = stripe ?? new Stripe(env.STRIPE_SECRET_KEY!, { timeout: 8_000, maxNetworkRetries: 1 });
  const checks: Check[] = [];
  const expectedLive = env.STRIPE_MODE === 'live';
  for (const [key, definition] of Object.entries(priceCatalog)) {
    const id = env[definition.env];
    if (!id) continue;
    try {
      const price = await api.prices.retrieve(id, { expand: ['product'] });
      const product = typeof price.product === 'string' ? undefined : price.product;
      const valid = price.active && price.livemode === expectedLive && price.currency === 'usd' && price.unit_amount === definition.amount && price.type === 'recurring' && price.recurring?.interval === definition.interval && price.recurring.interval_count === 1 && price.lookup_key === stripeLookupKeys[key as keyof typeof priceCatalog] && product && !product.deleted && product.active && product.livemode === expectedLive && product.metadata.farda_catalog_key === definition.tier;
      checks.push({ name: `stripe.remote_price.${key}`, status: valid ? 'pass' : 'fail', detail: valid ? 'active price and product match catalog, lookup key, and mode' : 'price or product does not match the catalog, lookup key, or mode' });
    } catch { checks.push({ name: `stripe.remote_price.${key}`, status: 'fail', detail: 'could not retrieve configured Price ID' }); }
  }
  try {
    const portals = await api.billingPortal.configurations.list({ active: true, limit: 10 });
    const portal = portals.data.find(item => item.is_default);
    const valid = portal?.livemode === expectedLive && portal.features.invoice_history.enabled && portal.features.payment_method_update.enabled && portal.features.subscription_cancel.enabled && portal.features.subscription_cancel.mode === 'at_period_end' && portal.features.subscription_cancel.proration_behavior === 'none' && !portal.features.subscription_update.enabled;
    checks.push({ name: 'stripe.customer_portal', status: valid ? 'pass' : 'fail', detail: valid ? 'default portal supports invoices, payment methods, and cancellation with plan switching disabled' : 'default portal configuration does not match the required feature policy' });
  } catch { checks.push({ name: 'stripe.customer_portal', status: 'fail', detail: 'could not read portal configurations' }); }

  const base = publicHttpsUrl(env.FARDA_PUBLIC_BASE_URL);
  if (!base) checks.push({ name: 'stripe.webhook_endpoint', status: 'blocked', detail: 'confirmed FARDA_PUBLIC_BASE_URL is required' });
  else try {
    const expectedUrl = new URL('/api/billing/webhook', base).href;
    const endpoints = await api.webhookEndpoints.list({ limit: 100 });
    const endpoint = endpoints.data.find(item => item.url === expectedUrl && item.status === 'enabled' && item.livemode === expectedLive);
    const events = new Set(endpoint?.enabled_events ?? []);
    const complete = endpoint && stripeWebhookEvents.every(event => events.has(event) || events.has('*'));
    checks.push({ name: 'stripe.webhook_endpoint', status: complete ? 'pass' : 'fail', detail: complete ? 'enabled endpoint has every required event' : 'matching enabled endpoint with every required event was not found' });
  } catch { checks.push({ name: 'stripe.webhook_endpoint', status: 'fail', detail: 'could not read webhook endpoints' }); }
  return checks;
}

export async function inspectPhotonRemote(env: RuntimeEnvironment, fetcher: typeof fetch = fetch): Promise<Check[]> {
  if (env.FARDA_REFILL_PROVIDER_ENVIRONMENT !== 'sandbox' && env.FARDA_REFILL_PROVIDER_ENVIRONMENT !== 'production') return [{ name: 'photon.remote_auth', status: 'blocked', detail: 'FARDA_REFILL_PROVIDER_ENVIRONMENT must be sandbox or production' }];
  if (!configured(env.PHOTON_CLIENT_ID) || !configured(env.PHOTON_CLIENT_SECRET)) return [{ name: 'photon.remote_auth', status: 'blocked', detail: 'Photon credentials are missing' }];
  const production = env.FARDA_REFILL_PROVIDER_ENVIRONMENT === 'production';
  const origin = production ? 'https://auth.photon.health' : 'https://auth.neutron.health';
  const audience = production ? 'https://api.photon.health' : 'https://api.neutron.health';
  try {
    const response = await fetcher(`${origin}/oauth/token`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ client_id: env.PHOTON_CLIENT_ID, client_secret: env.PHOTON_CLIENT_SECRET, audience, grant_type: 'client_credentials' }), redirect: 'error', signal: AbortSignal.timeout(8_000) });
    if (!response.ok) { void response.body?.cancel(); return [{ name: 'photon.remote_auth', status: 'fail', detail: `authentication rejected with HTTP ${response.status}` }]; }
    const body = await response.json() as { access_token?: unknown; token_type?: unknown };
    return [{ name: 'photon.remote_auth', status: typeof body.access_token === 'string' && body.token_type === 'Bearer' ? 'pass' : 'fail', detail: typeof body.access_token === 'string' && body.token_type === 'Bearer' ? 'credentials accepted; no patient data read and no order submitted' : 'authentication response was invalid' }];
  } catch { return [{ name: 'photon.remote_auth', status: 'fail', detail: 'authentication request failed' }]; }
}

async function main() {
  const args = new Set(process.argv.slice(2));
  if ([...args].some(arg => arg !== '--remote')) throw new Error('Usage: pnpm runtime:readiness [--remote]');
  const checks = inspectRuntime(process.env);
  if (args.has('--remote')) checks.push(...await inspectStripeRemote(process.env), ...await inspectPhotonRemote(process.env));
  for (const check of checks) process.stdout.write(`${check.status.toUpperCase()} ${check.name}: ${check.detail}\n`);
  if (checks.some(check => check.status !== 'pass')) process.exitCode = 1;
}

if (require.main === module) void main().catch(() => { process.stderr.write('Runtime readiness check failed without changing provider configuration.\n'); process.exitCode = 1; });
