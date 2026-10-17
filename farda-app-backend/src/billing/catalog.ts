import { exactPublicOrigins, publicHttpsUrl, stripePriceId, stripeSecretKeyMatchesMode } from '../common/activation';

export const priceCatalog = {
  plus_monthly: { tier: 'plus', interval: 'month', amount: 1499, env: 'STRIPE_PRICE_PLUS_MONTHLY' },
  plus_annual: { tier: 'plus', interval: 'year', amount: 14999, env: 'STRIPE_PRICE_PLUS_ANNUAL' },
  family_monthly: { tier: 'family', interval: 'month', amount: 2499, env: 'STRIPE_PRICE_FAMILY_MONTHLY' },
  family_annual: { tier: 'family', interval: 'year', amount: 24999, env: 'STRIPE_PRICE_FAMILY_ANNUAL' },
} as const;
export type PriceKey = keyof typeof priceCatalog;
export type PaidTier = 'plus' | 'family';

export function configuredPrices(env: NodeJS.ProcessEnv = process.env) {
  return Object.fromEntries(Object.entries(priceCatalog).flatMap(([key, value]) => {
    const id = env[value.env];
    return id ? [[key, { ...value, id }]] : [];
  })) as Partial<Record<PriceKey, (typeof priceCatalog)[PriceKey] & { id: string }>>;
}

export function stripeActivationReady(env: NodeJS.ProcessEnv = process.env) {
  const ids = Object.values(priceCatalog).map(definition => env[definition.env]);
  return stripeSecretKeyMatchesMode(env) && /^whsec_[A-Za-z0-9_]+$/.test(env.STRIPE_WEBHOOK_SECRET ?? '') &&
    ids.every(stripePriceId) && new Set(ids).size === ids.length && Boolean(exactPublicOrigins(env.FARDA_BILLING_RETURN_ORIGINS)) &&
    Boolean(publicHttpsUrl(env.FARDA_PUBLIC_BASE_URL, true));
}

export function publicCatalog(env: NodeJS.ProcessEnv = process.env) {
  const configured = configuredPrices(env);
  const benefitsReady = env.FARDA_REFILL_AI_ENABLED === 'true' && Boolean(env.OPENAI_API_KEY);
  const tierReady = (tier: PaidTier) => benefitsReady && (tier !== 'family' || env.FARDA_REMINDER_WORKER_ENABLED === 'true');
  const plan = (tier: PaidTier, capabilities: string[]) => ({
    tier, capabilities,
    prices: Object.entries(priceCatalog).filter(([, p]) => p.tier === tier).map(([key, p]) => ({ key, interval: p.interval, amount: p.amount, available: tierReady(tier) && Boolean(configured[key as PriceKey]) })),
  });
  return { currency: 'USD', plans: [plan('plus', ['ai_refill_help']), plan('family', ['ai_refill_help', 'family_alerts'])], checkoutEnabled: env.STRIPE_BILLING_ENABLED === 'true' && benefitsReady && stripeActivationReady(env), nativePurchases: { supported: false, reason: 'not_configured' } };
}
