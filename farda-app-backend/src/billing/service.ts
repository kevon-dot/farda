import Stripe from 'stripe';
import type { PrismaClient } from '../../generated/prisma/client';
import { configuredPrices, priceCatalog, publicCatalog, stripeActivationReady, type PaidTier, type PriceKey } from './catalog';
import { nativeEntitled, refreshNativeIfNeeded } from './native';

export class BillingError extends Error { constructor(public status: number, public code: string, message: string) { super(message); } }
type Db = Pick<PrismaClient, 'billingCustomer' | 'billingSubscription' | 'billingWebhookEvent' | 'billingCheckout' | 'nativeBillingSubscription' | '$transaction'>;
const validUrl = (raw: string) => { const url = new URL(raw); const origins = (process.env.FARDA_BILLING_RETURN_ORIGINS ?? '').split(',').map(x => x.trim()).filter(Boolean); if (!origins.includes(url.origin)) throw new BillingError(400, 'invalid_url', 'Return URL origin is not allowed.'); return url.toString(); };
const objectId = (value: string | { id: string } | null | undefined) => typeof value === 'string' ? value : value?.id;

function eventSubscriptionId(event: Stripe.Event) {
  if (event.type.startsWith('customer.subscription.')) return (event.data.object as Stripe.Subscription).id;
  if (event.type === 'invoice.paid' || event.type === 'invoice.payment_failed') {
    const invoice = event.data.object as Stripe.Invoice;
    const subscription = invoice.parent?.subscription_details?.subscription ?? (invoice as Stripe.Invoice & { subscription?: string | Stripe.Subscription | null }).subscription;
    return objectId(subscription);
  }
  if (event.type === 'checkout.session.completed' || event.type === 'checkout.session.async_payment_succeeded' || event.type === 'checkout.session.async_payment_failed') {
    return objectId((event.data.object as Stripe.Checkout.Session).subscription);
  }
  return undefined;
}

export class BillingService {
  private readonly prices = configuredPrices();
  constructor(private readonly db: Db, private readonly stripe?: Stripe) {}
  catalog() { return publicCatalog(); }
  private provider() { if (process.env.STRIPE_BILLING_ENABLED !== 'true' || !this.stripe || !stripeActivationReady()) throw new BillingError(503, 'billing_unavailable', 'Billing is not configured.'); return this.stripe; }
  async status(userId: string) {
    const row = await this.db.billingSubscription.findFirst({ where: { userId }, orderBy: { updatedAt: 'desc' } });
    const entitled = await this.db.billingSubscription.findFirst({ where: { userId, tier: { in: ['plus', 'family'] }, status: { in: ['active', 'trialing'] }, currentPeriodEnd: { gt: new Date() } }, orderBy: { updatedAt: 'desc' } });
    const native = this.db.nativeBillingSubscription ? await refreshNativeIfNeeded(this.db, userId) ?? await this.db.nativeBillingSubscription.findUnique({ where: { userId } }) : null;
    const freshNative = nativeEntitled(native, 'ai_refill_help') ? native : null;
    const paid = (entitled?.tier === 'family' || freshNative?.tier === 'family' ? 'family' : entitled?.tier === 'plus' || freshNative?.tier === 'plus' ? 'plus' : undefined) as PaidTier | undefined;
    const activeSources = [...(entitled ? ['web' as const] : []), ...(freshNative ? ['native' as const] : [])];
    const source = activeSources.length === 2 ? 'multiple' : activeSources[0] ?? (row ? 'web' : native?.everPurchased ? 'native' : null);
    const selected = source === 'native' ? freshNative : source === 'web' ? row : null;
    const management = { web: Boolean(row && this.stripe), native: Boolean(native?.everPurchased) };
    return { tier: paid ?? 'free', status: source === 'multiple' ? 'provider_conflict' : selected?.status ?? row?.status ?? (native?.everPurchased ? native.status : 'inactive'), capabilities: { core: true, aiRefillHelp: Boolean(paid), familyAlerts: paid === 'family' }, renewsAt: (source === 'native' ? freshNative?.expiresAt : source === 'web' ? row?.currentPeriodEnd : null)?.toISOString() ?? null, cancelAtPeriodEnd: source === 'web' ? row?.cancelAtPeriodEnd ?? false : false, managementAvailable: management.web || management.native, source, activeSources, management };
  }
  private async customer(userId: string) {
    const existing = await this.db.billingCustomer.findUnique({ where: { userId } });
    if (existing) return existing.stripeCustomerId;
    const customer = await this.provider().customers.create({ metadata: { fardaUserId: userId } });
    try { await this.db.billingCustomer.create({ data: { userId, stripeCustomerId: customer.id } }); return customer.id; }
    catch { const winner = await this.db.billingCustomer.findUnique({ where: { userId } }); if (winner) return winner.stripeCustomerId; throw new BillingError(503, 'billing_unavailable', 'Billing is temporarily unavailable.'); }
  }
  async checkout(userId: string, input: { priceKey: PriceKey; successUrl: string; cancelUrl: string; channel: 'web' }) {
    if (input.channel !== 'web') throw new BillingError(409, 'native_purchase_required', 'This purchase channel is not available.');
    const selected = this.prices[input.priceKey];
    if (!selected || !priceCatalog[input.priceKey]) throw new BillingError(400, 'unknown_price', 'That price is not available.');
    if (process.env.FARDA_REFILL_AI_ENABLED !== 'true' || !process.env.OPENAI_API_KEY) throw new BillingError(503, 'benefit_unavailable', 'Paid benefits are not available.');
    if (selected.tier === 'family' && process.env.FARDA_REMINDER_WORKER_ENABLED !== 'true') throw new BillingError(503, 'benefit_unavailable', 'Family alerts are not available.');
    const successUrl = validUrl(input.successUrl), cancelUrl = validUrl(input.cancelUrl);
    const stripe = this.provider();
    const price = await stripe.prices.retrieve(selected.id);
    const expectedLive = process.env.STRIPE_MODE === 'live';
    if (!price.active || price.livemode !== expectedLive || price.currency !== 'usd' || price.unit_amount !== selected.amount || price.recurring?.interval !== selected.interval || price.recurring?.interval_count !== 1) throw new BillingError(503, 'price_mismatch', 'Billing price configuration is invalid.');
    const active = await this.db.billingSubscription.findFirst({ where: { userId, status: { in: ['active', 'trialing'] }, currentPeriodEnd: { gt: new Date() } }, select: { id: true } });
    if (active) throw new BillingError(409, 'subscription_exists', 'Manage the existing subscription instead.');
    const native = this.db.nativeBillingSubscription ? await this.db.nativeBillingSubscription.findUnique({ where: { userId } }) : null;
    if (nativeEntitled(native, 'ai_refill_help')) throw new BillingError(409, 'subscription_exists', 'Manage the existing subscription instead.');
    const customer = await this.customer(userId);
    const remote = await stripe.subscriptions.list({ customer, status: 'all', limit: 100 });
    if (remote.data.some(subscription => ['active', 'trialing', 'past_due', 'unpaid', 'incomplete'].includes(subscription.status))) throw new BillingError(409, 'subscription_exists', 'Manage the existing subscription instead.');
    const expiresAt = new Date(Date.now() + 31 * 60_000);
    const reusable = await this.db.$transaction(async tx => {
      await tx.$executeRawUnsafe('SELECT pg_advisory_xact_lock(hashtext($1))', `billing:${userId}`);
      const lockedNative = await tx.nativeBillingSubscription.findUnique({ where: { userId } });
      if (nativeEntitled(lockedNative, 'ai_refill_help')) throw new BillingError(409, 'subscription_exists', 'Manage the existing subscription instead.');
      if (lockedNative?.purchaseReservedUntil && lockedNative.purchaseReservedUntil > new Date()) throw new BillingError(409, 'checkout_in_progress', 'A native purchase is already in progress.');
      const now = new Date();
      const prior = await tx.billingCheckout.findUnique({ where: { userId } });
      if (prior && prior.expiresAt > now) {
        if (prior.priceKey !== input.priceKey) throw new BillingError(409, 'checkout_in_progress', 'Another checkout is already in progress.');
        if (prior.stripeSessionId && prior.sessionUrl) return { stripeSessionId: prior.stripeSessionId, sessionUrl: prior.sessionUrl };
        else throw new BillingError(409, 'checkout_in_progress', 'Checkout is being prepared.');
      }
      if (prior) await tx.billingCheckout.deleteMany({ where: { userId, expiresAt: { lte: now } } });
      await tx.billingCheckout.create({ data: { userId, priceKey: input.priceKey, expiresAt } });
      return null;
    });
    if (reusable) {
      const existing = await stripe.checkout.sessions.retrieve(reusable.stripeSessionId);
      if (existing.status === 'open') return { url: reusable.sessionUrl };
      throw new BillingError(409, 'checkout_in_progress', 'Another checkout is already in progress.');
    }
    const session = await stripe.checkout.sessions.create({ mode: 'subscription', customer, line_items: [{ price: selected.id, quantity: 1 }], success_url: successUrl, cancel_url: cancelUrl, subscription_data: { metadata: { fardaUserId: userId } }, allow_promotion_codes: true, expires_at: Math.floor(expiresAt.getTime() / 1000) }, { idempotencyKey: `farda-checkout-${userId}-${expiresAt.getTime()}` });
    if (!session.url) throw new BillingError(503, 'billing_unavailable', 'Checkout is temporarily unavailable.');
    await this.db.billingCheckout.update({ where: { userId }, data: { stripeSessionId: session.id, sessionUrl: session.url } });
    return { url: session.url };
  }
  async portal(userId: string, returnUrl: string) {
    const customer = await this.db.billingCustomer.findUnique({ where: { userId } });
    if (!customer) throw new BillingError(404, 'billing_customer_not_found', 'No billing account exists.');
    const session = await this.provider().billingPortal.sessions.create({ customer: customer.stripeCustomerId, return_url: validUrl(returnUrl) });
    return { url: session.url };
  }
  async webhook(raw: Buffer, signature: string | undefined) {
    if (!signature) throw new BillingError(400, 'invalid_signature', 'Missing webhook signature.');
    const stripe = this.provider();
    let event: Stripe.Event;
    try { event = stripe.webhooks.constructEvent(raw, signature, process.env.STRIPE_WEBHOOK_SECRET!); }
    catch { throw new BillingError(400, 'invalid_signature', 'Invalid webhook signature.'); }
    if (await this.db.billingWebhookEvent.findUnique({ where: { stripeEventId: event.id } })) return { duplicate: true };
    const expectedLive = process.env.STRIPE_MODE === 'live';
    if (event.livemode !== expectedLive) throw new BillingError(400, 'mode_mismatch', 'Webhook mode does not match billing configuration.');
    const subscriptionId = eventSubscriptionId(event);
    if (subscriptionId) {
      const delivered = event.type.startsWith('customer.subscription.') ? event.data.object as Stripe.Subscription : undefined;
      // Stripe doesn't guarantee event delivery order. Retrieve canonical state
      // for non-deletion events instead of trusting a possibly stale payload.
      const canonical = event.type === 'customer.subscription.deleted' ? delivered! : await this.provider().subscriptions.retrieve(subscriptionId, { expand: ['latest_invoice'] });
      if (canonical.livemode !== expectedLive) throw new BillingError(400, 'mode_mismatch', 'Subscription mode does not match billing configuration.');
      const run = async (db: Db) => { await this.reconcile(canonical, event.created, expectedLive, db); };
      if (typeof this.db.$transaction === 'function') {
        await this.db.$transaction(async tx => {
          await tx.$executeRawUnsafe('SELECT pg_advisory_xact_lock(hashtext($1))', subscriptionId);
          // Re-read after acquiring the cross-worker lock. The first retrieve
          // may have raced another webhook's provider update.
          const lockedCanonical = event.type === 'customer.subscription.deleted' ? delivered! : await this.provider().subscriptions.retrieve(subscriptionId, { expand: ['latest_invoice'] });
          if (lockedCanonical.livemode !== expectedLive) throw new BillingError(400, 'mode_mismatch', 'Subscription mode does not match billing configuration.');
          await this.reconcile(lockedCanonical, event.created, expectedLive, tx as unknown as Db);
        }, { timeout: 15_000 });
      } else await run(this.db);
    }
    try { await this.db.billingWebhookEvent.create({ data: { stripeEventId: event.id, type: event.type } }); }
    catch (error) { if (await this.db.billingWebhookEvent.findUnique({ where: { stripeEventId: event.id } })) return { duplicate: true }; throw error; }
    return { received: true };
  }
  private async paymentConfirmed(subscription: Stripe.Subscription, expectedLive: boolean) {
    if (subscription.status !== 'active') return false;
    const latest = subscription.latest_invoice;
    if (!latest) return false;
    const invoice = typeof latest === 'string' ? await this.provider().invoices.retrieve(latest) : latest;
    const subscriptionCustomerId = objectId(subscription.customer);
    const invoiceCustomerId = objectId(invoice.customer);
    return invoice.livemode === expectedLive && invoice.status === 'paid' && invoiceCustomerId === subscriptionCustomerId;
  }
  private async reconcile(subscription: Stripe.Subscription, eventCreated: number, expectedLive: boolean, db: Db = this.db) {
    const customerId = typeof subscription.customer === 'string' ? subscription.customer : subscription.customer.id;
    const owner = await db.billingCustomer.findUnique({ where: { stripeCustomerId: customerId } });
    if (!owner) return; // Never bind an event to metadata alone.
    const priceId = subscription.items.data[0]?.price.id ?? 'unknown';
    const match = Object.entries(this.prices).find(([, p]) => p.id === priceId);
    const item = subscription.items.data[0] as Stripe.SubscriptionItem & { current_period_end?: number };
    const lastEventCreatedAt = new Date(eventCreated * 1000);
    const existing = await db.billingSubscription.findUnique({ where: { stripeSubscriptionId: subscription.id }, select: { userId: true, lastEventCreatedAt: true } });
    if (existing?.userId !== undefined && existing.userId !== owner.userId) return;
    // The object is either a fresh canonical retrieve or a terminal deletion.
    // Preserve the monotonic marker without discarding authoritative state just
    // because the event that triggered reconciliation arrived late.
    const effectiveEventAt = existing && existing.lastEventCreatedAt > lastEventCreatedAt ? existing.lastEventCreatedAt : lastEventCreatedAt;
    // An unknown/unconfigured price revokes local benefits for an existing row.
    // It cannot create or transfer an entitlement.
    if (!match) {
      if (existing) await db.billingSubscription.updateMany({ where: { stripeSubscriptionId: subscription.id, userId: owner.userId }, data: { priceId, tier: 'none', status: subscription.status, lastEventCreatedAt: effectiveEventAt } });
      return;
    }
    const [key] = match as [PriceKey, unknown];
    const paid = await this.paymentConfirmed(subscription, expectedLive);
    const data = { priceId, tier: paid ? priceCatalog[key].tier : 'none', status: subscription.status, currentPeriodEnd: item.current_period_end ? new Date(item.current_period_end * 1000) : null, cancelAtPeriodEnd: subscription.cancel_at_period_end, lastEventCreatedAt: effectiveEventAt };
    if (existing) { await db.billingSubscription.updateMany({ where: { stripeSubscriptionId: subscription.id, userId: owner.userId }, data }); return; }
    try { await db.billingSubscription.create({ data: { userId: owner.userId, stripeSubscriptionId: subscription.id, stripeCustomerId: customerId, ...data } }); }
    catch (error) {
      const winner = await db.billingSubscription.findUnique({ where: { stripeSubscriptionId: subscription.id }, select: { userId: true, lastEventCreatedAt: true } });
      if (!winner) throw error;
      if (winner.userId !== owner.userId) return;
      await db.billingSubscription.updateMany({ where: { stripeSubscriptionId: subscription.id, userId: owner.userId, lastEventCreatedAt: { lte: lastEventCreatedAt } }, data });
    }
  }
}

export function createBillingService(db: Db) { return new BillingService(db, process.env.STRIPE_SECRET_KEY ? new Stripe(process.env.STRIPE_SECRET_KEY, { timeout: 8_000, maxNetworkRetries: 1 }) : undefined); }
