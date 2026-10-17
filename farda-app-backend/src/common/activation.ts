import { isIP } from 'node:net';

export type RuntimeEnvironment = Record<string, string | undefined>;

export const configured = (value?: string) => Boolean(value?.trim());

const isPlaceholder = (value: string) =>
  /(?:^|\.)(?:localhost|local)$|example\.(?:com|org|net)$|your-host|\.invalid$/i.test(value);

function privateIpv4(address: string) {
  const octets = address.split('.').map(Number);
  return octets[0] === 0 || octets[0] === 10 || octets[0] === 127 ||
    (octets[0] === 100 && octets[1] >= 64 && octets[1] <= 127) ||
    (octets[0] === 169 && octets[1] === 254) ||
    (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) ||
    (octets[0] === 192 && ((octets[1] === 0 && (octets[2] === 0 || octets[2] === 2)) || octets[1] === 168)) ||
    (octets[0] === 198 && (octets[1] === 18 || octets[1] === 19 || (octets[1] === 51 && octets[2] === 100))) ||
    (octets[0] === 203 && octets[1] === 0 && octets[2] === 113) || octets[0] >= 224;
}

function mappedIpv4(address: string) {
  if (!address.startsWith('::ffff:')) return undefined;
  const suffix = address.slice(7);
  if (isIP(suffix) === 4) return suffix;
  const groups = suffix.split(':');
  if (groups.length !== 2 || groups.some(group => !/^[0-9a-f]{1,4}$/.test(group))) return undefined;
  const values = groups.map(group => Number.parseInt(group, 16));
  return `${values[0] >> 8}.${values[0] & 255}.${values[1] >> 8}.${values[1] & 255}`;
}

/** Rejects known local, private, reserved, and placeholder HTTPS destinations without resolving DNS. */
export function publicHttpsUrl(value?: string, originOnly = false): URL | undefined {
  if (!value || value !== value.trim()) return undefined;
  try {
    const url = new URL(value);
    const hostname = url.hostname.replace(/^\[|\]$/g, '').toLowerCase();
    const mapped = mappedIpv4(hostname);
    const privateIpv6 = hostname === '::' || hostname === '::1' || /^(fc|fd)/.test(hostname) ||
      /^fe[89ab]/.test(hostname) || /^ff/.test(hostname) || /^2001:db8(?:0*:|$)/.test(hostname) ||
      (mapped !== undefined && privateIpv4(mapped));
    const privateAddress = isIP(hostname) === 4 ? privateIpv4(hostname) : isIP(hostname) === 6 && privateIpv6;
    if (url.protocol !== 'https:' || url.username || url.password || !hostname || isPlaceholder(hostname) || privateAddress || url.hash) return undefined;
    if (originOnly && (url.href !== `${url.origin}/` || url.pathname !== '/' || url.search)) return undefined;
    return url;
  } catch { return undefined; }
}

export const exactPublicOrigins = (raw?: string) => {
  const values = (raw ?? '').split(',').map(value => value.trim()).filter(Boolean);
  return values.length > 0 && new Set(values).size === values.length &&
    values.every(value => publicHttpsUrl(value, true)?.origin === value) ? values : undefined;
};

export const stripeMode = (env: RuntimeEnvironment) => env.STRIPE_MODE === 'test' || env.STRIPE_MODE === 'live'
  ? env.STRIPE_MODE : undefined;

export const stripeSecretKeyMatchesMode = (env: RuntimeEnvironment) => {
  const mode = stripeMode(env);
  if (!mode) return false;
  return (mode === 'live' ? /^(?:sk|rk)_live_[A-Za-z0-9]+$/ : /^(?:sk|rk)_test_[A-Za-z0-9]+$/)
    .test(env.STRIPE_SECRET_KEY ?? '');
};

export const stripePriceId = (value?: string) => /^price_[A-Za-z0-9]+$/.test(value ?? '');

export const revenueCatProductVariables = [
  ['ios', 'plus', 'REVENUECAT_IOS_PLUS_PRODUCT_IDS'],
  ['ios', 'family', 'REVENUECAT_IOS_FAMILY_PRODUCT_IDS'],
  ['android', 'plus', 'REVENUECAT_ANDROID_PLUS_PRODUCT_IDS'],
  ['android', 'family', 'REVENUECAT_ANDROID_FAMILY_PRODUCT_IDS'],
] as const;

export const csv = (env: RuntimeEnvironment, name: string) =>
  (env[name] ?? '').split(',').map(value => value.trim()).filter(Boolean);

export function revenueCatProductConfiguration(env: RuntimeEnvironment) {
  const entries = revenueCatProductVariables.flatMap(([platform, tier, name]) =>
    csv(env, name).map(id => ({ platform, tier, name, id })));
  const counts = new Map(entries.map(entry => [entry.id, (entries.filter(item => item.id === entry.id).length)]));
  const valid = revenueCatProductVariables.every(([, , name]) => csv(env, name).length > 0) && entries.every(entry => {
    const pattern = entry.platform === 'ios'
      ? /^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$/
      : /^[A-Za-z0-9][A-Za-z0-9._-]{0,254}(?::[A-Za-z0-9][A-Za-z0-9._-]{0,254})?$/;
    return pattern.test(entry.id) && counts.get(entry.id) === 1;
  });
  return { entries, valid };
}

export function revenueCatActivationReady(env: RuntimeEnvironment) {
  const mode = env.REVENUECAT_MODE;
  const entitlements = [env.REVENUECAT_PLUS_ENTITLEMENT_ID, env.REVENUECAT_FAMILY_ENTITLEMENT_ID];
  const publicKeys = /^appl_[A-Za-z0-9]+$/.test(env.REVENUECAT_IOS_PUBLIC_API_KEY ?? '') &&
    /^goog_[A-Za-z0-9]+$/.test(env.REVENUECAT_ANDROID_PUBLIC_API_KEY ?? '');
  const secretKey = /^sk_[A-Za-z0-9]+$/.test(env.REVENUECAT_SECRET_API_KEY ?? '');
  const webhook = configured(env.REVENUECAT_WEBHOOK_AUTH_TOKEN) &&
    (env.REVENUECAT_WEBHOOK_AUTH_TOKEN?.trim().length ?? 0) >= 24;
  const entitlementIds = entitlements.every(value => /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(value ?? '')) &&
    new Set(entitlements).size === entitlements.length;
  return (mode === 'sandbox' || mode === 'live') && publicKeys && secretKey && webhook && entitlementIds &&
    revenueCatProductConfiguration(env).valid && Boolean(publicHttpsUrl(env.FARDA_TERMS_URL)) &&
    Boolean(publicHttpsUrl(env.FARDA_PRIVACY_URL)) && Boolean(publicHttpsUrl(env.FARDA_SUPPORT_URL)) &&
    Boolean(publicHttpsUrl(env.FARDA_PUBLIC_BASE_URL, true));
}

export function photonActivationReady(env: RuntimeEnvironment) {
  return (env.FARDA_REFILL_PROVIDER_ENVIRONMENT === 'sandbox' || env.FARDA_REFILL_PROVIDER_ENVIRONMENT === 'production') &&
    configured(env.PHOTON_CLIENT_ID) && configured(env.PHOTON_CLIENT_SECRET) &&
    env.PHOTON_CLIENT_ID?.trim() !== env.PHOTON_CLIENT_SECRET?.trim();
}
