import Stripe from 'stripe';

const products = [
  { key: 'plus', name: 'Farda Plus', description: 'Optional AI refill navigation help.' },
  { key: 'family', name: 'Farda Family', description: 'Plus benefits and opt-in family alerts.' },
] as const;
const prices = [
  { lookup: 'farda_plus_monthly_usd', product: 'plus', amount: 1499, interval: 'month' },
  { lookup: 'farda_plus_annual_usd', product: 'plus', amount: 14999, interval: 'year' },
  { lookup: 'farda_family_monthly_usd', product: 'family', amount: 2499, interval: 'month' },
  { lookup: 'farda_family_annual_usd', product: 'family', amount: 24999, interval: 'year' },
] as const;

type PriceDefinition = (typeof prices)[number];

export function assertReusablePrice(price: Stripe.Price, definition: PriceDefinition, productId: string) {
  const actualProductId = typeof price.product === 'string' ? price.product : price.product.id;
  const matches = price.active && !price.livemode && price.currency === 'usd' &&
    price.unit_amount === definition.amount && price.type === 'recurring' &&
    price.recurring?.interval === definition.interval && price.recurring.interval_count === 1 &&
    actualProductId === productId;
  if (!matches) {
    throw new Error(`Refusing catalog bootstrap: existing lookup key ${definition.lookup} does not match the expected test price.`);
  }
}

async function main() {
  const key = process.env.STRIPE_SECRET_KEY;
  if (process.env.STRIPE_MODE !== 'test' || !(key?.startsWith('sk_test_') || key?.startsWith('rk_test_'))) {
    throw new Error('Refusing catalog bootstrap: STRIPE_MODE=test and an sk_test_ or rk_test_ key are required.');
  }
  const stripe = new Stripe(key);
  const productIds = new Map<string, string>();
  for (const definition of products) {
    const existing = await stripe.products.search({ query: `active:'true' AND metadata['farda_catalog_key']:'${definition.key}'`, limit: 1 });
    const product = existing.data[0] ?? await stripe.products.create({ name: definition.name, description: definition.description, metadata: { farda_catalog_key: definition.key, environment: 'test' } });
    if (product.livemode) throw new Error(`Refusing catalog bootstrap: product ${definition.key} is not in test mode.`);
    productIds.set(definition.key, product.id);
  }
  for (const definition of prices) {
    const productId = productIds.get(definition.product)!;
    const existing = await stripe.prices.list({ lookup_keys: [definition.lookup], limit: 1 });
    if (existing.data.length) {
      assertReusablePrice(existing.data[0], definition, productId);
      continue;
    }
    await stripe.prices.create({ currency: 'usd', unit_amount: definition.amount, recurring: { interval: definition.interval }, product: productId, lookup_key: definition.lookup, metadata: { environment: 'test' } });
  }
  const configured = await stripe.prices.list({ lookup_keys: prices.map(price => price.lookup), active: true, limit: 10 });
  for (const price of configured.data) console.log(`${price.lookup_key}=${price.id}`);
}

if (require.main === module) void main();
