import Stripe from 'stripe';

const key = process.env.STRIPE_SECRET_KEY;
if (process.env.STRIPE_MODE !== 'test' || !key?.startsWith('sk_test_')) {
  throw new Error('Refusing catalog bootstrap: STRIPE_MODE=test and an sk_test_ key are required.');
}
const stripe = new Stripe(key);
const products = [
  { key: 'plus', name: 'Farda Plus', description: 'Optional AI refill navigation help.' },
  { key: 'family', name: 'Farda Family', description: 'Plus benefits and opt-in family alerts.' },
] as const;
const prices = [
  { lookup: 'farda_plus_monthly_usd', product: 'plus', amount: 699, interval: 'month' },
  { lookup: 'farda_plus_annual_usd', product: 'plus', amount: 5999, interval: 'year' },
  { lookup: 'farda_family_monthly_usd', product: 'family', amount: 1199, interval: 'month' },
  { lookup: 'farda_family_annual_usd', product: 'family', amount: 9999, interval: 'year' },
] as const;

const productIds = new Map<string, string>();
for (const definition of products) {
  const existing = await stripe.products.search({ query: `active:'true' AND metadata['farda_catalog_key']:'${definition.key}'`, limit: 1 });
  const product = existing.data[0] ?? await stripe.products.create({ name: definition.name, description: definition.description, metadata: { farda_catalog_key: definition.key, environment: 'test' } });
  productIds.set(definition.key, product.id);
}
for (const definition of prices) {
  const existing = await stripe.prices.list({ lookup_keys: [definition.lookup], active: true, limit: 1 });
  if (existing.data.length) continue;
  await stripe.prices.create({ currency: 'usd', unit_amount: definition.amount, recurring: { interval: definition.interval }, product: productIds.get(definition.product)!, lookup_key: definition.lookup, metadata: { environment: 'test' } });
}
const configured = await stripe.prices.list({ lookup_keys: prices.map(price => price.lookup), active: true, limit: 10 });
for (const price of configured.data) console.log(`${price.lookup_key}=${price.id}`);
