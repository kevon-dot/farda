import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import type { PrismaClient } from '../../generated/prisma/client';
import { BillingError } from './service';

type NativeDb = Pick<PrismaClient, 'user' | 'billingSubscription' | 'billingCheckout' | 'nativeBillingSubscription' | 'nativeBillingWebhookEvent' | '$transaction'>;
type Platform = 'ios' | 'android';
type Tier = 'plus' | 'family';

type RevenueCatSubscription = {
  expires_date?: string | null;
  store?: string;
  is_sandbox?: boolean;
  billing_issues_detected_at?: string | null;
  refunded_at?: string | null;
  ownership_type?: string;
};
type RevenueCatSubscriber = {
  subscriber?: {
    original_app_user_id?: string;
    entitlements?: Record<string, { expires_date?: string | null; product_identifier?: string }>;
    subscriptions?: Record<string, RevenueCatSubscription>;
  };
};

const csv = (name: string) => (process.env[name] ?? '').split(',').map(value => value.trim()).filter(Boolean);
const enabled = () => process.env.REVENUECAT_NATIVE_BILLING_ENABLED === 'true';
const validMode = () => process.env.REVENUECAT_MODE === 'sandbox' || process.env.REVENUECAT_MODE === 'live';
const publicHttpsUrl = (name: string) => {
  try { const url = new URL(process.env[name] ?? ''); return url.protocol === 'https:' && !url.username && !url.password ? url.toString() : undefined; }
  catch { return undefined; }
};
const configurationReady = () => Boolean(
  enabled() && validMode() && process.env.REVENUECAT_SECRET_API_KEY && process.env.REVENUECAT_WEBHOOK_AUTH_TOKEN &&
  process.env.REVENUECAT_IOS_PUBLIC_API_KEY && process.env.REVENUECAT_ANDROID_PUBLIC_API_KEY &&
  process.env.REVENUECAT_PLUS_ENTITLEMENT_ID && process.env.REVENUECAT_FAMILY_ENTITLEMENT_ID &&
  (csv('REVENUECAT_IOS_PLUS_PRODUCT_IDS').length + csv('REVENUECAT_ANDROID_PLUS_PRODUCT_IDS').length) > 0 &&
  (csv('REVENUECAT_IOS_FAMILY_PRODUCT_IDS').length + csv('REVENUECAT_ANDROID_FAMILY_PRODUCT_IDS').length) > 0 &&
  publicHttpsUrl('FARDA_TERMS_URL') && publicHttpsUrl('FARDA_PRIVACY_URL'),
);
const tierAvailable = (tier: Tier) => process.env.FARDA_REFILL_AI_ENABLED === 'true' && Boolean(process.env.OPENAI_API_KEY) && (tier !== 'family' || process.env.FARDA_REMINDER_WORKER_ENABLED === 'true');
const maxStaleMs = () => {
  const seconds = Number(process.env.REVENUECAT_MAX_STALE_SECONDS ?? 86400);
  return Number.isFinite(seconds) && seconds >= 60 ? seconds * 1000 : 0;
};

function productMap() {
  const map = new Map<string, { tier: Tier; platform: Platform }>();
  for (const [platform, tier, name] of [
    ['ios', 'plus', 'REVENUECAT_IOS_PLUS_PRODUCT_IDS'], ['ios', 'family', 'REVENUECAT_IOS_FAMILY_PRODUCT_IDS'],
    ['android', 'plus', 'REVENUECAT_ANDROID_PLUS_PRODUCT_IDS'], ['android', 'family', 'REVENUECAT_ANDROID_FAMILY_PRODUCT_IDS'],
  ] as const) for (const id of csv(name)) {
    if (map.has(id)) throw new BillingError(503, 'native_billing_misconfigured', 'Native billing product configuration is ambiguous.');
    map.set(id, { tier, platform });
  }
  return map;
}

function authorized(actual: string | undefined) {
  const expected = process.env.REVENUECAT_WEBHOOK_AUTH_TOKEN;
  if (!expected || !actual) return false;
  const a = createHash('sha256').update(actual).digest();
  const b = createHash('sha256').update(expected).digest();
  return timingSafeEqual(a, b);
}

export class NativeBillingService {
  constructor(private readonly db: NativeDb, private readonly fetcher: typeof fetch = fetch) {}

  private response(platform: Platform, appUserId: string) {
    const products = productMap();
    return {
      enabled: true as const, platform, appUserId,
      apiKey: platform === 'ios' ? process.env.REVENUECAT_IOS_PUBLIC_API_KEY! : process.env.REVENUECAT_ANDROID_PUBLIC_API_KEY!,
      entitlements: { plus: process.env.REVENUECAT_PLUS_ENTITLEMENT_ID!, family: process.env.REVENUECAT_FAMILY_ENTITLEMENT_ID! },
      products: [...products].filter(([, value]) => value.platform === platform && tierAvailable(value.tier)).map(([id, value]) => ({ id, tier: value.tier })),
      termsUrl: publicHttpsUrl('FARDA_TERMS_URL')!, privacyUrl: publicHttpsUrl('FARDA_PRIVACY_URL')!,
    };
  }

  private ready() {
    if (!configurationReady()) throw new BillingError(503, 'native_billing_unavailable', 'Native billing is not configured.');
  }

  private async identity(userId: string) {
    const existing = await this.db.nativeBillingSubscription.findUnique({ where: { userId } });
    if (existing) return existing;
    const appUserId = `farda_${randomBytes(24).toString('base64url')}`;
    try {
      return await this.db.nativeBillingSubscription.create({ data: { userId, revenueCatAppUserId: appUserId, tier: 'none', status: 'inactive', lastSyncedAt: new Date(0) } });
    } catch {
      const winner = await this.db.nativeBillingSubscription.findUnique({ where: { userId } });
      if (winner) return winner;
      throw new BillingError(503, 'native_billing_unavailable', 'Native billing is temporarily unavailable.');
    }
  }

  async config(userId: string, platform: Platform) {
    if (!configurationReady()) return { enabled: false as const };
    if (platform === 'android' && process.env.REVENUECAT_ANDROID_CONTRACT_VERIFIED !== 'true') return { enabled: false as const, reason: 'store_contract_unverified' as const };
    const web = await this.db.billingSubscription.findFirst({ where: { userId, status: { in: ['active', 'trialing', 'past_due', 'unpaid', 'incomplete'] } }, select: { id: true } });
    if (web) return { enabled: false as const, reason: 'web_subscription_active' as const };
    const identity = await this.identity(userId);
    if (this.response(platform, identity.revenueCatAppUserId).products.length === 0) return { enabled: false as const, reason: 'benefits_unavailable' as const };
    return this.response(platform, identity.revenueCatAppUserId);
  }

  async prepare(userId: string, platform: Platform) {
    this.ready();
    if (platform === 'android' && process.env.REVENUECAT_ANDROID_CONTRACT_VERIFIED !== 'true') throw new BillingError(503, 'native_billing_unavailable', 'Android billing has not been verified.');
    return this.db.$transaction(async tx => {
      await tx.$executeRawUnsafe('SELECT pg_advisory_xact_lock(hashtext($1))', `billing:${userId}`);
      const web = await tx.billingSubscription.findFirst({ where: { userId, status: { in: ['active', 'trialing', 'past_due', 'unpaid', 'incomplete'] } }, select: { id: true } });
      const checkout = await tx.billingCheckout.findUnique({ where: { userId } });
      if (web || (checkout && checkout.expiresAt > new Date())) throw new BillingError(409, 'subscription_exists', 'A web subscription or checkout already exists.');
      const identity = await tx.nativeBillingSubscription.findUnique({ where: { userId } }) ?? await tx.nativeBillingSubscription.create({ data: { userId, revenueCatAppUserId: `farda_${randomBytes(24).toString('base64url')}`, tier: 'none', status: 'inactive', lastSyncedAt: new Date(0) } });
      if (identity.status === 'active' && (!identity.expiresAt || identity.expiresAt > new Date())) throw new BillingError(409, 'subscription_exists', 'Manage the existing subscription instead.');
      if (identity.purchaseReservedUntil && identity.purchaseReservedUntil > new Date()) throw new BillingError(409, 'checkout_in_progress', 'A native purchase is already in progress.');
      await tx.nativeBillingSubscription.update({ where: { userId }, data: { purchaseReservedUntil: new Date(Date.now() + 10 * 60_000), purchasePlatform: platform } });
      return this.response(platform, identity.revenueCatAppUserId);
    });
  }

  private async subscriber(appUserId: string): Promise<RevenueCatSubscriber> {
    this.ready();
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    try {
      const response = await this.fetcher(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`, {
        headers: { Authorization: `Bearer ${process.env.REVENUECAT_SECRET_API_KEY!}`, Accept: 'application/json' }, signal: controller.signal, redirect: 'error',
      });
      if (!response.ok) throw new BillingError(503, 'native_billing_unavailable', 'Native billing verification failed.');
      return await response.json() as RevenueCatSubscriber;
    } finally { clearTimeout(timeout); }
  }

  async sync(userId: string) {
    const identity = await this.identity(userId);
    return this.reconcileLocked(userId, identity.revenueCatAppUserId);
  }

  private async reconcileLocked(userId: string, appUserId: string) {
    return this.db.$transaction(async tx => {
      await tx.$executeRawUnsafe('SELECT pg_advisory_xact_lock(hashtext($1))', `native-billing:${userId}`);
      return this.reconcile(tx as unknown as NativeDb, userId, appUserId);
    }, { timeout: 15_000 });
  }

  private async reconcile(db: NativeDb, userId: string, appUserId: string) {
    const payload = await this.subscriber(appUserId);
    const subscriber = payload.subscriber;
    if (!subscriber || subscriber.original_app_user_id !== appUserId || typeof subscriber.entitlements !== 'object' || typeof subscriber.subscriptions !== 'object' || Array.isArray(subscriber.entitlements) || Array.isArray(subscriber.subscriptions)) throw new BillingError(503, 'native_billing_invalid_response', 'Native billing verification failed.');
    const expectedSandbox = process.env.REVENUECAT_MODE === 'sandbox';
    const products = productMap();
    const candidates: Array<{ tier: Tier; productId: string; expiresAt: Date | null; store: string }> = [];
    const entitlementIds: Array<[Tier, string]> = [['plus', process.env.REVENUECAT_PLUS_ENTITLEMENT_ID!], ['family', process.env.REVENUECAT_FAMILY_ENTITLEMENT_ID!]];
    for (const [tier, entitlementId] of entitlementIds) {
      const entitlement = subscriber.entitlements[entitlementId];
      const productId = entitlement?.product_identifier;
      // Android entitlement IDs include the base plan (`product:baseplan`),
      // while the v1 subscriptions map may be keyed by the bare product.
      const subscription = productId ? subscriber.subscriptions[productId] ?? subscriber.subscriptions[productId.split(':')[0]!] : undefined;
      const configured = productId ? products.get(productId) : undefined;
      const entitlementExpiry = entitlement?.expires_date ? new Date(entitlement.expires_date) : null;
      const subscriptionExpiry = subscription?.expires_date ? new Date(subscription.expires_date) : null;
      const validDates = entitlementExpiry && subscriptionExpiry && !Number.isNaN(entitlementExpiry.getTime()) && !Number.isNaN(subscriptionExpiry.getTime());
      const expiresAt = validDates ? new Date(Math.min(entitlementExpiry.getTime(), subscriptionExpiry.getTime())) : null;
      const expectedStore = configured?.platform === 'ios' ? 'app_store' : 'play_store';
      if (entitlement && productId && subscription && configured?.tier === tier && subscription.is_sandbox === expectedSandbox &&
        subscription.store === expectedStore && subscription.ownership_type === 'PURCHASED' && expiresAt && expiresAt > new Date() && !subscription.billing_issues_detected_at && !subscription.refunded_at) {
        candidates.push({ tier, productId, expiresAt, store: subscription.store ?? configured.platform });
      }
    }
    candidates.sort((a, b) => (a.tier === 'family' ? -1 : 1) - (b.tier === 'family' ? -1 : 1));
    const active = candidates[0];
    return db.nativeBillingSubscription.update({ where: { userId, revenueCatAppUserId: appUserId }, data: {
      tier: active?.tier ?? 'none', status: active ? 'active' : 'inactive', productId: active?.productId ?? null,
      store: active?.store ?? null, isSandbox: active ? expectedSandbox : null, expiresAt: active?.expiresAt ?? null, lastSyncedAt: new Date(),
      lastVerificationAttemptAt: new Date(),
      ...(active ? { everPurchased: true, purchaseReservedUntil: null, purchasePlatform: null } : {}),
    } });
  }

  async webhook(body: unknown, authorization: string | undefined) {
    this.ready();
    if (!authorized(authorization)) throw new BillingError(401, 'invalid_signature', 'Invalid webhook authorization.');
    const event = (body as { event?: { id?: unknown; type?: unknown; app_user_id?: unknown; transferred_from?: unknown; transferred_to?: unknown } })?.event;
    if (!event || typeof event.id !== 'string' || typeof event.type !== 'string') throw new BillingError(400, 'invalid_webhook', 'Invalid webhook payload.');
    const eventId = event.id, eventType = event.type;
    if (await this.db.nativeBillingWebhookEvent.findUnique({ where: { revenueCatEventId: eventId } })) return { duplicate: true };
    if (event.type === 'TRANSFER') {
      const ids = [...(Array.isArray(event.transferred_from) ? event.transferred_from : []), ...(Array.isArray(event.transferred_to) ? event.transferred_to : [])].filter((id): id is string => typeof id === 'string');
      try {
        await this.db.$transaction(async tx => {
          const rows = await tx.nativeBillingSubscription.findMany({ where: { revenueCatAppUserId: { in: ids } }, select: { userId: true } });
          for (const userId of [...new Set(rows.map(row => row.userId))].sort()) await tx.$executeRawUnsafe('SELECT pg_advisory_xact_lock(hashtext($1))', `native-billing:${userId}`);
          await tx.nativeBillingSubscription.updateMany({ where: { revenueCatAppUserId: { in: ids } }, data: { tier: 'none', status: 'transfer_rejected', productId: null, store: null, isSandbox: null, expiresAt: null, lastSyncedAt: new Date(), lastVerificationAttemptAt: new Date() } });
          await tx.nativeBillingWebhookEvent.create({ data: { revenueCatEventId: eventId, type: eventType } });
        });
      } catch (error) {
        if (await this.db.nativeBillingWebhookEvent.findUnique({ where: { revenueCatEventId: eventId } })) return { duplicate: true };
        throw error;
      }
      return { received: true };
    }
    if (typeof event.app_user_id !== 'string') throw new BillingError(400, 'invalid_webhook', 'Invalid webhook payload.');
    const identity = await this.db.nativeBillingSubscription.findUnique({ where: { revenueCatAppUserId: event.app_user_id } });
    if (!identity) throw new BillingError(400, 'unknown_customer', 'Unknown native billing customer.');
    await this.reconcileLocked(identity.userId, identity.revenueCatAppUserId);
    try { await this.db.nativeBillingWebhookEvent.create({ data: { revenueCatEventId: event.id, type: event.type } }); }
    catch (error) {
      if (await this.db.nativeBillingWebhookEvent.findUnique({ where: { revenueCatEventId: event.id } })) return { duplicate: true };
      throw error;
    }
    return { received: true };
  }
}

export function nativeEntitled(row: { tier: string; status: string; productId: string | null; store: string | null; isSandbox: boolean | null; expiresAt: Date | null; lastSyncedAt: Date } | null | undefined, capability: 'ai_refill_help' | 'family_alerts') {
  if (!configurationReady() || !row || row.status !== 'active' || !row.expiresAt || Date.now() - row.lastSyncedAt.getTime() > maxStaleMs() || row.expiresAt <= new Date()) return false;
  const configured = row.productId ? productMap().get(row.productId) : undefined;
  if (!configured || configured.tier !== row.tier || row.store !== (configured.platform === 'ios' ? 'app_store' : 'play_store') || row.isSandbox !== (process.env.REVENUECAT_MODE === 'sandbox')) return false;
  if (!tierAvailable(row.tier as Tier)) return false;
  return capability === 'family_alerts' ? row.tier === 'family' : row.tier === 'plus' || row.tier === 'family';
}

// Refresh halfway through the bounded trust window. The database claim limits
// provider retries across API and worker processes; a failed fetch never extends trust.
export async function refreshNativeIfNeeded(db: unknown, userId: string) {
  if (!configurationReady()) return null;
  const nativeDb = db as NativeDb;
  if (!nativeDb.nativeBillingSubscription || !nativeDb.$transaction) return null;
  let row = await nativeDb.nativeBillingSubscription.findUnique({ where: { userId } });
  if (!row || row.status !== 'active' || Date.now() - row.lastSyncedAt.getTime() < maxStaleMs() / 2) return row;
  const retryBefore = new Date(Date.now() - 5 * 60_000);
  const claim = await nativeDb.nativeBillingSubscription.updateMany({ where: { userId, OR: [{ lastVerificationAttemptAt: null }, { lastVerificationAttemptAt: { lt: retryBefore } }] }, data: { lastVerificationAttemptAt: new Date() } });
  if (claim.count) {
    try { row = await new NativeBillingService(nativeDb).sync(userId); }
    catch { row = await nativeDb.nativeBillingSubscription.findUnique({ where: { userId } }); }
  }
  return row;
}
