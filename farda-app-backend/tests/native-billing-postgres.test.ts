import { randomUUID } from 'node:crypto';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../generated/prisma/client';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { NativeBillingService } from '../src/billing/native';
import { BillingService } from '../src/billing/service';

const url = process.env.TEST_DATABASE_URL;
describe.skipIf(!url)('native and web billing PostgreSQL reservation boundary', () => {
  let db: PrismaClient; const userId = `native-billing-${randomUUID()}`, nativeRaceUserId = `native-race-${randomUUID()}`;
  const savedEnv = { ...process.env };
  beforeAll(async () => { db = new PrismaClient({ adapter: new PrismaPg({ connectionString: url!, max: 6 }) }); await db.user.createMany({ data: [{ id: userId }, { id: nativeRaceUserId }] }); await db.billingCustomer.create({ data: { userId, stripeCustomerId: `cus_${randomUUID()}` } }); });
  afterAll(async () => { if (db) { await db.user.deleteMany({ where: { id: { in: [userId, nativeRaceUserId] } } }); await db.$disconnect(); } process.env = { ...savedEnv }; });
  it('allows only one first purchase reservation across simultaneous native prepare and web checkout', async () => {
    Object.assign(process.env, { REVENUECAT_NATIVE_BILLING_ENABLED: 'true', REVENUECAT_MODE: 'sandbox', REVENUECAT_SECRET_API_KEY: 'secret', REVENUECAT_WEBHOOK_AUTH_TOKEN: 'auth', REVENUECAT_IOS_PUBLIC_API_KEY: 'ios', REVENUECAT_ANDROID_PUBLIC_API_KEY: 'android', REVENUECAT_PLUS_ENTITLEMENT_ID: 'plus', REVENUECAT_FAMILY_ENTITLEMENT_ID: 'family', REVENUECAT_IOS_PLUS_PRODUCT_IDS: 'ios.plus', REVENUECAT_IOS_FAMILY_PRODUCT_IDS: 'ios.family', REVENUECAT_ANDROID_PLUS_PRODUCT_IDS: 'android.plus:monthly', REVENUECAT_ANDROID_FAMILY_PRODUCT_IDS: 'android.family:monthly', FARDA_TERMS_URL: 'https://example.test/terms', FARDA_PRIVACY_URL: 'https://example.test/privacy', FARDA_REFILL_AI_ENABLED: 'true', OPENAI_API_KEY: 'test', FARDA_REMINDER_WORKER_ENABLED: 'true', STRIPE_BILLING_ENABLED: 'true', STRIPE_WEBHOOK_SECRET: 'secret', STRIPE_PRICE_PLUS_MONTHLY: 'price_plus', FARDA_BILLING_RETURN_ORIGINS: 'https://app.test' });
    const stripe: any = { prices: { retrieve: async () => ({ active: true, livemode: false, currency: 'usd', unit_amount: 1499, recurring: { interval: 'month', interval_count: 1 } }) }, subscriptions: { list: async () => ({ data: [] }) }, checkout: { sessions: { create: async () => ({ id: 'cs', url: 'https://checkout.test/session' }), retrieve: async () => ({ status: 'open' }) } } };
    const results = await Promise.allSettled([new NativeBillingService(db).prepare(userId, 'ios'), new BillingService(db, stripe).checkout(userId, { priceKey: 'plus_monthly', successUrl: 'https://app.test/s', cancelUrl: 'https://app.test/c', channel: 'web' })]);
    expect(results.filter(result => result.status === 'fulfilled')).toHaveLength(1);
    expect(results.find(result => result.status === 'rejected')).toMatchObject({ reason: { status: 409 } });
  }, 30_000);
  it('allows only one native purchase reservation across simultaneous devices and platforms', async () => {
    process.env.REVENUECAT_ANDROID_CONTRACT_VERIFIED = 'true';
    const service = new NativeBillingService(db);
    const results = await Promise.allSettled([service.prepare(nativeRaceUserId, 'ios'), service.prepare(nativeRaceUserId, 'android')]);
    expect(results.filter(result => result.status === 'fulfilled')).toHaveLength(1);
    expect(results.find(result => result.status === 'rejected')).toMatchObject({ reason: { status: 409, code: 'checkout_in_progress' } });
    const row = await db.nativeBillingSubscription.findUnique({ where: { userId: nativeRaceUserId } });
    expect(row?.purchaseReservedUntil?.getTime()).toBeGreaterThan(Date.now());
    expect(['ios', 'android']).toContain(row?.purchasePlatform);
  }, 30_000);
});
