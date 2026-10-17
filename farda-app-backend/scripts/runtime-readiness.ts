import Stripe from 'stripe';
import {
  configured, exactPublicOrigins, photonActivationReady, publicHttpsUrl, revenueCatActivationReady,
  revenueCatProductConfiguration, revenueCatProductVariables, stripeMode, stripePriceId, stripeSecretKeyMatchesMode,
  type RuntimeEnvironment,
} from '../src/common/activation';
import { priceCatalog, stripeActivationReady } from '../src/billing/catalog';

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

const flagCheck = (name: string, value: string | undefined): Check => ({
  name, status: value === 'true' || value === 'false' ? 'pass' : 'fail',
  detail: value === 'true' || value === 'false' ? `${value} selected` : 'must be exactly true or false',
});

export function inspectRuntime(env: RuntimeEnvironment): Check[] {
  const checks: Check[] = [];
  const mode = stripeMode(env);
  checks.push({ name: 'stripe.mode', status: mode ? 'pass' : 'fail', detail: mode ? `${mode} mode selected` : 'STRIPE_MODE must be test or live' });
  checks.push({ name: 'stripe.secret_key', status: stripeSecretKeyMatchesMode(env) ? 'pass' : 'fail', detail: stripeSecretKeyMatchesMode(env) ? 'present; mode prefix checked' : 'STRIPE_SECRET_KEY is missing, malformed, or incompatible with STRIPE_MODE' });
  const stripeWebhookSecret = /^whsec_[A-Za-z0-9_]+$/.test(env.STRIPE_WEBHOOK_SECRET ?? '');
  checks.push({ name: 'stripe.webhook_secret', status: stripeWebhookSecret ? 'pass' : 'fail', detail: stripeWebhookSecret ? 'present; format checked' : 'STRIPE_WEBHOOK_SECRET is missing or malformed' });

  const priceIds: string[] = [];
  for (const [key, definition] of Object.entries(priceCatalog)) {
    const value = env[definition.env];
    if (value) priceIds.push(value);
    checks.push({ name: `stripe.price.${key}`, status: stripePriceId(value) ? 'pass' : 'fail', detail: stripePriceId(value) ? `${definition.env} has a Price ID` : `${definition.env} is missing or malformed` });
  }
  const uniquePrices = priceIds.length === Object.keys(priceCatalog).length && new Set(priceIds).size === priceIds.length;
  checks.push({ name: 'stripe.prices_unique', status: uniquePrices ? 'pass' : 'fail', detail: uniquePrices ? 'every catalog slot has a distinct Price ID' : 'Stripe Price IDs must be complete and distinct' });

  const origins = exactPublicOrigins(env.FARDA_BILLING_RETURN_ORIGINS);
  checks.push({ name: 'stripe.return_origins', status: origins ? 'pass' : 'fail', detail: origins ? `${origins.length} distinct HTTPS origin(s) configured` : 'FARDA_BILLING_RETURN_ORIGINS needs distinct, exact, non-placeholder HTTPS origins' });

  const base = publicHttpsUrl(env.FARDA_PUBLIC_BASE_URL, true);
  checks.push({ name: 'webhook.public_url', status: base ? 'pass' : 'blocked', detail: base ? `public API origin is configured` : 'FARDA_PUBLIC_BASE_URL is not an exact public HTTPS origin' });
  checks.push({ name: 'stripe.webhook_url', status: base ? 'pass' : 'blocked', detail: base ? `expected endpoint ${new URL('/api/billing/webhook', base).href}` : 'public API origin is required for the Stripe webhook' });

  const revenueCatMode = env.REVENUECAT_MODE === 'sandbox' || env.REVENUECAT_MODE === 'live';
  checks.push({ name: 'revenuecat.mode', status: revenueCatMode ? 'pass' : 'fail', detail: revenueCatMode ? `${env.REVENUECAT_MODE} mode selected` : 'REVENUECAT_MODE must be sandbox or live' });
  const rcSecret = /^sk_[A-Za-z0-9]+$/.test(env.REVENUECAT_SECRET_API_KEY ?? '');
  checks.push({ name: 'revenuecat.secret_key', status: rcSecret ? 'pass' : 'fail', detail: rcSecret ? 'private API key format checked' : 'REVENUECAT_SECRET_API_KEY is missing or malformed' });
  for (const [platform, pattern, variable] of [
    ['ios', /^appl_[A-Za-z0-9]+$/, 'REVENUECAT_IOS_PUBLIC_API_KEY'],
    ['android', /^goog_[A-Za-z0-9]+$/, 'REVENUECAT_ANDROID_PUBLIC_API_KEY'],
  ] as const) {
    const valid = pattern.test(env[variable] ?? '');
    checks.push({ name: `revenuecat.${platform}_public_key`, status: valid ? 'pass' : 'fail', detail: valid ? `${variable} format checked` : `${variable} is missing or malformed` });
  }
  const webhookAuth = configured(env.REVENUECAT_WEBHOOK_AUTH_TOKEN) &&
    (env.REVENUECAT_WEBHOOK_AUTH_TOKEN?.trim().length ?? 0) >= 24;
  checks.push({ name: 'revenuecat.webhook_auth', status: webhookAuth ? 'pass' : 'fail', detail: webhookAuth ? 'authorization token is present and nontrivial' : 'REVENUECAT_WEBHOOK_AUTH_TOKEN must contain at least 24 characters' });
  const entitlementPattern = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;
  const entitlements = [env.REVENUECAT_PLUS_ENTITLEMENT_ID, env.REVENUECAT_FAMILY_ENTITLEMENT_ID];
  const validEntitlements = entitlements.every(value => entitlementPattern.test(value ?? '')) && new Set(entitlements).size === 2;
  checks.push({ name: 'revenuecat.entitlements', status: validEntitlements ? 'pass' : 'fail', detail: validEntitlements ? 'Plus and Family entitlement IDs are valid and distinct' : 'Plus and Family entitlement IDs must be valid and distinct' });
  const productConfiguration = revenueCatProductConfiguration(env);
  for (const [platform, tier, variable] of revenueCatProductVariables) {
    const entries = productConfiguration.entries.filter(entry => entry.name === variable);
    const valid = entries.length > 0 && entries.every(entry => productConfiguration.entries.filter(item => item.id === entry.id).length === 1) &&
      (platform === 'ios' ? entries.every(entry => /^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$/.test(entry.id)) : entries.every(entry => /^[A-Za-z0-9][A-Za-z0-9._-]{0,254}(?::[A-Za-z0-9][A-Za-z0-9._-]{0,254})?$/.test(entry.id)));
    checks.push({ name: `revenuecat.products.${platform}_${tier}`, status: valid ? 'pass' : 'fail', detail: valid ? `${entries.length} distinct product ID(s) configured` : `${variable} is missing, malformed, or duplicates another tier/platform` });
  }
  for (const [name, variable] of [['legal.terms_url', 'FARDA_TERMS_URL'], ['legal.privacy_url', 'FARDA_PRIVACY_URL'], ['support.url', 'FARDA_SUPPORT_URL']] as const) {
    const valid = publicHttpsUrl(env[variable]);
    checks.push({ name, status: valid ? 'pass' : 'fail', detail: valid ? `${variable} is a public HTTPS URL` : `${variable} must be a non-placeholder public HTTPS URL` });
  }
  checks.push({ name: 'revenuecat.webhook_url', status: base ? 'pass' : 'blocked', detail: base ? `expected endpoint ${new URL('/api/billing/native/webhook', base).href}` : 'public API origin is required for the RevenueCat webhook' });

  const photonEnvironment = env.FARDA_REFILL_PROVIDER_ENVIRONMENT;
  checks.push({ name: 'photon.environment', status: photonEnvironment === 'sandbox' || photonEnvironment === 'production' ? 'pass' : 'fail', detail: photonEnvironment === 'sandbox' || photonEnvironment === 'production' ? `${photonEnvironment} selected` : 'FARDA_REFILL_PROVIDER_ENVIRONMENT must be sandbox or production' });
  for (const key of ['PHOTON_CLIENT_ID', 'PHOTON_CLIENT_SECRET'] as const) {
    checks.push({ name: `photon.${key === 'PHOTON_CLIENT_ID' ? 'client_id' : 'client_secret'}`, status: configured(env[key]) ? 'pass' : 'fail', detail: configured(env[key]) ? `${key} is present` : `${key} is missing` });
  }
  const distinctPhotonCredentials = configured(env.PHOTON_CLIENT_ID) && configured(env.PHOTON_CLIENT_SECRET) && env.PHOTON_CLIENT_ID?.trim() !== env.PHOTON_CLIENT_SECRET?.trim();
  checks.push({ name: 'photon.credentials_distinct', status: distinctPhotonCredentials ? 'pass' : 'fail', detail: distinctPhotonCredentials ? 'client ID and secret are distinct' : 'Photon client ID and secret must be present and distinct' });

  const stripeEnabled = env.STRIPE_BILLING_ENABLED === 'true';
  const revenueCatEnabled = env.REVENUECAT_NATIVE_BILLING_ENABLED === 'true';
  const photonEnabled = env.FARDA_REFILL_PROVIDER_ENABLED === 'true';
  checks.push(flagCheck('stripe.enablement_flag', env.STRIPE_BILLING_ENABLED));
  checks.push({ name: 'stripe.enablement', status: stripeEnabled && !stripeActivationReady(env) ? 'fail' : 'pass', detail: stripeEnabled ? 'enabled with complete local activation configuration' : 'disabled (safe default)' });
  checks.push(flagCheck('revenuecat.enablement_flag', env.REVENUECAT_NATIVE_BILLING_ENABLED));
  checks.push({ name: 'revenuecat.enablement', status: revenueCatEnabled && !revenueCatActivationReady(env) ? 'fail' : 'pass', detail: revenueCatEnabled ? 'enabled with complete local activation configuration' : 'disabled (safe default)' });
  checks.push(flagCheck('photon.enablement_flag', env.FARDA_REFILL_PROVIDER_ENABLED));
  checks.push({ name: 'photon.enablement', status: photonEnabled && !photonActivationReady(env) ? 'fail' : 'pass', detail: photonEnabled ? 'enabled with complete local activation configuration' : 'disabled (safe default)' });
  return checks;
}

export async function inspectStripeRemote(env: RuntimeEnvironment, stripe?: Stripe): Promise<Check[]> {
  if (!stripeActivationReady(env)) return [{ name: 'stripe.remote', status: 'blocked', detail: 'complete compatible local Stripe configuration is required before remote verification' }];
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

  const base = publicHttpsUrl(env.FARDA_PUBLIC_BASE_URL, true);
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
  if (!photonActivationReady(env)) return [{ name: 'photon.remote_auth', status: 'blocked', detail: 'complete compatible Photon configuration is required before remote verification' }];
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
