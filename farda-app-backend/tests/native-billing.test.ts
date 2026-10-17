import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { NativeBillingService, nativeEntitled } from '../src/billing/native';

const saved = { ...process.env };
beforeEach(() => Object.assign(process.env, {
  REVENUECAT_NATIVE_BILLING_ENABLED: 'true', REVENUECAT_MODE: 'sandbox', REVENUECAT_SECRET_API_KEY: 'sk_secret',
  REVENUECAT_WEBHOOK_AUTH_TOKEN: 'Bearer webhook-secret-long-enough', REVENUECAT_IOS_PUBLIC_API_KEY: 'appl_public', REVENUECAT_ANDROID_PUBLIC_API_KEY: 'goog_public',
  REVENUECAT_PLUS_ENTITLEMENT_ID: 'plus', REVENUECAT_FAMILY_ENTITLEMENT_ID: 'family', REVENUECAT_IOS_PLUS_PRODUCT_IDS: 'farda_plus',
  REVENUECAT_IOS_FAMILY_PRODUCT_IDS: 'farda_family', REVENUECAT_ANDROID_PLUS_PRODUCT_IDS: 'farda_plus:monthly',
  REVENUECAT_ANDROID_FAMILY_PRODUCT_IDS: 'farda_family:monthly', FARDA_TERMS_URL: 'https://legal.example.test/terms', FARDA_PRIVACY_URL: 'https://legal.example.test/privacy',
  FARDA_SUPPORT_URL: 'https://support.example.test/help', FARDA_PUBLIC_BASE_URL: 'https://api.example.test',
  FARDA_REFILL_AI_ENABLED: 'true', OPENAI_API_KEY: 'test', FARDA_REMINDER_WORKER_ENABLED: 'true',
}));
afterEach(() => { process.env = { ...saved }; });

function fixture(payload: unknown) {
  const row: any = { userId: 'user', revenueCatAppUserId: 'farda_opaque', tier: 'none', status: 'inactive', productId: null, store: null, isSandbox: null, expiresAt: null, lastSyncedAt: new Date(0) };
  const events = new Set<string>();
  const db: any = {
    nativeBillingSubscription: {
      findUnique: vi.fn(async ({ where }: any) => where.userId === 'user' || where.revenueCatAppUserId === row.revenueCatAppUserId ? row : null),
      findMany: vi.fn(async ({ where }: any) => where.revenueCatAppUserId.in.includes(row.revenueCatAppUserId) ? [{ userId: row.userId }] : []),
      create: vi.fn(), update: vi.fn(async ({ data }: any) => Object.assign(row, data)),
      updateMany: vi.fn(async ({ where, data }: any) => where.revenueCatAppUserId.in.includes(row.revenueCatAppUserId) ? (Object.assign(row, data), { count: 1 }) : { count: 0 }),
    },
    nativeBillingWebhookEvent: { findUnique: vi.fn(async ({ where }: any) => events.has(where.revenueCatEventId) ? {} : null), create: vi.fn(async ({ data }: any) => { events.add(data.revenueCatEventId); }) },
    billingSubscription: { findFirst: vi.fn(async () => null) }, billingCheckout: { findUnique: vi.fn(async () => null) },
    $transaction: vi.fn(async (fn: any) => fn({ ...db, $executeRawUnsafe: vi.fn() })),
  };
  const fetcher = vi.fn(async () => new Response(JSON.stringify(payload), { status: 200 }));
  return { row, db, fetcher, service: new NativeBillingService(db, fetcher as any) };
}

const canonical = (overrides: Record<string, unknown> = {}) => ({ subscriber: { original_app_user_id: 'farda_opaque', entitlements: { plus: { product_identifier: 'farda_plus', expires_date: '2030-01-01T00:00:00Z' } }, subscriptions: { farda_plus: { expires_date: '2030-01-01T00:00:00Z', store: 'app_store', is_sandbox: true, ownership_type: 'PURCHASED' } }, ...overrides } });

describe('native billing verification', () => {
  it('grants only from a canonical matching entitlement, product, store and environment', async () => {
    const f = fixture(canonical()); await f.service.sync('user');
    expect(f.row).toMatchObject({ tier: 'plus', status: 'active', productId: 'farda_plus', store: 'app_store', isSandbox: true });
    expect(nativeEntitled(f.row, 'ai_refill_help')).toBe(true);
  });
  it.each([
    ['wrong owner', { original_app_user_id: 'someone_else' }],
    ['wrong store', { subscriptions: { farda_plus: { expires_date: '2030-01-01T00:00:00Z', store: 'play_store', is_sandbox: true, ownership_type: 'PURCHASED' } } }],
    ['wrong environment', { subscriptions: { farda_plus: { expires_date: '2030-01-01T00:00:00Z', store: 'app_store', is_sandbox: false, ownership_type: 'PURCHASED' } } }],
    ['missing subscription expiry', { subscriptions: { farda_plus: { store: 'app_store', is_sandbox: true, ownership_type: 'PURCHASED' } } }],
    ['refunded purchase', { subscriptions: { farda_plus: { expires_date: '2030-01-01T00:00:00Z', store: 'app_store', is_sandbox: true, ownership_type: 'PURCHASED', refunded_at: '2029-01-01T00:00:00Z' } } }],
    ['family shared purchase', { subscriptions: { farda_plus: { expires_date: '2030-01-01T00:00:00Z', store: 'app_store', is_sandbox: true, ownership_type: 'FAMILY_SHARED' } } }],
  ])('fails closed for %s', async (label, override) => {
    const f = fixture(canonical(override));
    if (label === 'wrong owner') await expect(f.service.sync('user')).rejects.toMatchObject({ code: 'native_billing_invalid_response' });
    else { await f.service.sync('user'); expect(f.row.tier).toBe('none'); }
  });
  it('rejects unauthenticated webhooks before provider or database writes', async () => {
    const f = fixture(canonical()); await expect(f.service.webhook({ event: { id: 'evt', type: 'RENEWAL', app_user_id: 'farda_opaque' } }, 'wrong')).rejects.toMatchObject({ code: 'invalid_signature' });
    expect(f.fetcher).not.toHaveBeenCalled(); expect(f.db.nativeBillingWebhookEvent.create).not.toHaveBeenCalled();
  });
  it('revokes both known sides of a transfer without accepting its new ownership', async () => {
    const f = fixture(canonical()); Object.assign(f.row, { tier: 'family', status: 'active', productId: 'farda_family', store: 'app_store', isSandbox: true, expiresAt: new Date('2030-01-01') });
    await f.service.webhook({ event: { id: 'transfer', type: 'TRANSFER', transferred_from: ['farda_opaque'], transferred_to: ['foreign'] } }, 'Bearer webhook-secret-long-enough');
    expect(f.row).toMatchObject({ tier: 'none', status: 'transfer_rejected', expiresAt: null }); expect(f.fetcher).not.toHaveBeenCalled();
  });
  it('invalidates a cached grant when product configuration changes or becomes stale', () => {
    const row = { tier: 'plus', status: 'active', productId: 'farda_plus', store: 'app_store', isSandbox: true, expiresAt: new Date('2030-01-01'), lastSyncedAt: new Date() };
    expect(nativeEntitled(row, 'ai_refill_help')).toBe(true); process.env.REVENUECAT_IOS_PLUS_PRODUCT_IDS = 'replacement'; expect(nativeEntitled(row, 'ai_refill_help')).toBe(false);
    process.env.REVENUECAT_IOS_PLUS_PRODUCT_IDS = 'farda_plus'; row.lastSyncedAt = new Date(0); expect(nativeEntitled(row, 'ai_refill_help')).toBe(false);
  });
  it('fails closed when the RevenueCat mode is missing or misspelled', async () => {
    const f = fixture(canonical());
    process.env.REVENUECAT_MODE = 'production';
    expect(await f.service.config('user', 'ios')).toEqual({ enabled: false });
    await expect(f.service.sync('user')).rejects.toMatchObject({ code: 'native_billing_unavailable' });
  });
  it('fails closed for a wrong platform key and returns validated support configuration', async () => {
    const f = fixture(canonical());
    const response = await f.service.config('user', 'ios');
    expect(response).toMatchObject({ enabled: true, supportUrl: 'https://support.example.test/help' });
    process.env.REVENUECAT_IOS_PUBLIC_API_KEY = 'goog_wrong';
    expect(await f.service.config('user', 'ios')).toEqual({ enabled: false });
  });
  it('does not clear a live purchase reservation when an early sync is still inactive', async () => {
    const f = fixture({ subscriber: { original_app_user_id: 'farda_opaque', entitlements: {}, subscriptions: {} } });
    f.row.purchaseReservedUntil = new Date(Date.now() + 600_000); f.row.purchasePlatform = 'ios';
    await f.service.sync('user');
    expect(f.row.purchaseReservedUntil.getTime()).toBeGreaterThan(Date.now());
    expect(f.row.purchasePlatform).toBe('ios');
  });
});
