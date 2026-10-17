import { describe, expect, it } from 'vitest';
import type Stripe from 'stripe';
import { assertReusablePrice } from '../scripts/bootstrap-stripe-test-catalog';
import { priceCatalog, publicCatalog } from '../src/billing/catalog';

describe('billing price catalog', () => {
  it('publishes the approved USD amounts in cents', () => {
    expect(priceCatalog).toMatchObject({
      plus_monthly: { amount: 1499, interval: 'month' },
      plus_annual: { amount: 14999, interval: 'year' },
      family_monthly: { amount: 2499, interval: 'month' },
      family_annual: { amount: 24999, interval: 'year' },
    });
    expect(publicCatalog({}).currency).toBe('USD');
  });

  it('keeps checkout disabled for incomplete or mode-incompatible activation', () => {
    const complete = {
      STRIPE_BILLING_ENABLED: 'true', STRIPE_MODE: 'test', STRIPE_SECRET_KEY: 'rk_test_synthetic',
      STRIPE_WEBHOOK_SECRET: 'whsec_synthetic', STRIPE_PRICE_PLUS_MONTHLY: 'price_plusmonthly',
      STRIPE_PRICE_PLUS_ANNUAL: 'price_plusannual', STRIPE_PRICE_FAMILY_MONTHLY: 'price_familymonthly',
      STRIPE_PRICE_FAMILY_ANNUAL: 'price_familyannual', FARDA_BILLING_RETURN_ORIGINS: 'https://app.test',
      FARDA_PUBLIC_BASE_URL: 'https://api.test', FARDA_REFILL_AI_ENABLED: 'true', OPENAI_API_KEY: 'synthetic',
    };
    expect(publicCatalog(complete).checkoutEnabled).toBe(true);
    expect(publicCatalog({ ...complete, STRIPE_SECRET_KEY: 'rk_live_wrongmode' }).checkoutEnabled).toBe(false);
    expect(publicCatalog({ ...complete, STRIPE_PRICE_FAMILY_ANNUAL: complete.STRIPE_PRICE_PLUS_ANNUAL }).checkoutEnabled).toBe(false);
    expect(publicCatalog({ ...complete, FARDA_PUBLIC_BASE_URL: 'https://127.0.0.1' }).checkoutEnabled).toBe(false);
  });

  it('refuses to reuse a lookup key with a different amount', () => {
    const definition = { lookup: 'farda_plus_monthly_usd', product: 'plus', amount: 1499, interval: 'month' } as const;
    const existing = {
      active: true,
      livemode: false,
      currency: 'usd',
      unit_amount: 699,
      type: 'recurring',
      recurring: { interval: 'month', interval_count: 1 },
      product: 'prod_plus',
    } as Stripe.Price;

    expect(() => assertReusablePrice(existing, definition, 'prod_plus')).toThrow(/does not match/);
  });

  it('reuses only an exact active test price for the expected product', () => {
    const definition = { lookup: 'farda_family_annual_usd', product: 'family', amount: 24999, interval: 'year' } as const;
    const existing = {
      active: true,
      livemode: false,
      currency: 'usd',
      unit_amount: 24999,
      type: 'recurring',
      recurring: { interval: 'year', interval_count: 1 },
      product: 'prod_family',
    } as Stripe.Price;

    expect(() => assertReusablePrice(existing, definition, 'prod_family')).not.toThrow();
    expect(() => assertReusablePrice(existing, definition, 'prod_other')).toThrow(/does not match/);
  });
});
