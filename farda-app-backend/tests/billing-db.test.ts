import { randomUUID } from "node:crypto";
import { PrismaPg } from "@prisma/adapter-pg";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { PrismaClient } from "../generated/prisma/client";
import { BillingService } from "../src/billing/service";

const databaseUrl = process.env.TEST_DATABASE_URL;

function subscription(overrides: Record<string, unknown> = {}) {
  return {
    id: "sub-placeholder",
    customer: "cus-placeholder",
    livemode: false,
    status: "active",
    cancel_at_period_end: false,
    items: {
      data: [
        {
          price: { id: "price_family_db" },
          current_period_end: Math.floor(Date.now() / 1000) + 86_400,
        },
      ],
    },
    ...overrides,
  };
}

function event(
  id: string,
  type: string,
  object: Record<string, unknown>,
  created = 1_800_000_000,
) {
  return { id, type, created, livemode: false, data: { object } };
}

describe.skipIf(!databaseUrl)("Billing PostgreSQL webhook serialization", () => {
  let db: PrismaClient;
  let service: BillingService;
  const prefix = `billing-it-${randomUUID()}`;
  const ownerId = `${prefix}-owner`;
  const otherId = `${prefix}-other`;
  const ownerCustomer = `cus_${prefix}_owner`;
  const otherCustomer = `cus_${prefix}_other`;
  const ownerSubscription = `sub_${prefix}_owner`;
  const foreignSubscription = `sub_${prefix}_foreign`;
  let canonical: Record<string, unknown>;
  let retrieve: ReturnType<typeof vi.fn>;

  beforeAll(async () => {
    process.env.STRIPE_BILLING_ENABLED = "true";
    process.env.STRIPE_WEBHOOK_SECRET = "whsec_billing_db_test";
    process.env.STRIPE_MODE = "test";
    process.env.STRIPE_PRICE_FAMILY_MONTHLY = "price_family_db";
    db = new PrismaClient({
      adapter: new PrismaPg({
        connectionString: databaseUrl!,
        max: process.env.TEST_DATABASE_SINGLE_CONNECTION === "true" ? 1 : 6,
      }),
    });
    await db.user.createMany({
      data: [
        { id: ownerId, name: "Synthetic billing owner" },
        { id: otherId, name: "Synthetic billing other" },
      ],
    });
    await db.billingCustomer.createMany({
      data: [
        { userId: ownerId, stripeCustomerId: ownerCustomer },
        { userId: otherId, stripeCustomerId: otherCustomer },
      ],
    });
  }, 30_000);

  beforeEach(async () => {
    await db.billingWebhookEvent.deleteMany({
      where: { stripeEventId: { startsWith: prefix } },
    });
    await db.billingSubscription.deleteMany({
      where: { userId: { in: [ownerId, otherId] } },
    });
    canonical = subscription({
      id: ownerSubscription,
      customer: ownerCustomer,
    });
    retrieve = vi.fn(async () => canonical);
    const stripe: any = {
      webhooks: {
        constructEvent: vi.fn((raw: Buffer, signature: string) => {
          if (signature !== "valid") throw new Error("invalid signature");
          return JSON.parse(raw.toString("utf8"));
        }),
      },
      subscriptions: { retrieve },
    };
    service = new BillingService(db, stripe);
  });

  afterAll(async () => {
    if (db) {
      await db.billingWebhookEvent.deleteMany({
        where: { stripeEventId: { startsWith: prefix } },
      });
      await db.user.deleteMany({ where: { id: { in: [ownerId, otherId] } } });
      await db.$disconnect();
    }
  });

  async function deliver(value: ReturnType<typeof event>) {
    return service.webhook(Buffer.from(JSON.stringify(value)), "valid");
  }

  it("persists active, same-second cancellation, and expired entitlement states", async () => {
    const created = 1_800_000_001;
    const active = subscription({ id: ownerSubscription, customer: ownerCustomer });
    canonical = active;
    await deliver(event(`${prefix}-active`, "customer.subscription.updated", active, created));
    expect(await service.status(ownerId)).toMatchObject({
      tier: "family",
      capabilities: { familyAlerts: true },
    });

    const canceled = subscription({
      id: ownerSubscription,
      customer: ownerCustomer,
      status: "canceled",
    });
    await deliver(event(`${prefix}-deleted`, "customer.subscription.deleted", canceled, created));
    expect(await db.billingSubscription.findUniqueOrThrow({
      where: { stripeSubscriptionId: ownerSubscription },
    })).toMatchObject({ userId: ownerId, status: "canceled" });
    expect(await service.status(ownerId)).toMatchObject({
      tier: "free",
      capabilities: { familyAlerts: false },
    });

    canonical = subscription({
      id: ownerSubscription,
      customer: ownerCustomer,
      items: {
        data: [
          {
            price: { id: "price_family_db" },
            current_period_end: Math.floor(Date.now() / 1000) - 60,
          },
        ],
      },
    });
    await deliver(event(`${prefix}-expired`, "customer.subscription.updated", canonical, created + 1));
    expect(await service.status(ownerId)).toMatchObject({
      tier: "free",
      capabilities: { familyAlerts: false },
    });
  });

  it("binds subscriptions only through the stored Stripe customer mapping", async () => {
    canonical = subscription({
      id: foreignSubscription,
      customer: otherCustomer,
      metadata: { fardaUserId: ownerId },
    });
    await deliver(event(`${prefix}-foreign`, "customer.subscription.updated", canonical));
    expect(await db.billingSubscription.findUniqueOrThrow({
      where: { stripeSubscriptionId: foreignSubscription },
    })).toMatchObject({ userId: otherId, stripeCustomerId: otherCustomer });
    expect(await db.billingSubscription.count({
      where: { stripeSubscriptionId: foreignSubscription, userId: ownerId },
    })).toBe(0);

    canonical = subscription({
      id: foreignSubscription,
      customer: ownerCustomer,
      status: "canceled",
    });
    await deliver(event(`${prefix}-collision`, "customer.subscription.updated", canonical, 1_800_000_001));
    expect(await db.billingSubscription.findUniqueOrThrow({
      where: { stripeSubscriptionId: foreignSubscription },
    })).toMatchObject({ userId: otherId, stripeCustomerId: otherCustomer, status: "active" });
  });

  it.skipIf(process.env.TEST_DATABASE_SINGLE_CONNECTION === "true")(
    "serializes concurrent reconciliation so an update cannot resurrect a cancellation",
    async () => {
      const created = 1_800_000_010;
      const active = subscription({ id: ownerSubscription, customer: ownerCustomer });
      const canceled = subscription({
        id: ownerSubscription,
        customer: ownerCustomer,
        status: "canceled",
      });
      let calls = 0;
      retrieve.mockImplementation(async () => {
        calls += 1;
        if (calls === 1) {
          canonical = canceled;
          return active;
        }
        return canonical;
      });
      canonical = active;

      await Promise.all([
        deliver(event(`${prefix}-race-update`, "customer.subscription.updated", active, created)),
        deliver(event(`${prefix}-race-delete`, "customer.subscription.deleted", canceled, created)),
      ]);

      const row = await db.billingSubscription.findUniqueOrThrow({
        where: { stripeSubscriptionId: ownerSubscription },
      });
      expect(row).toMatchObject({ userId: ownerId, status: "canceled" });
      expect(row.lastEventCreatedAt).toEqual(new Date(created * 1000));
      expect(await db.billingSubscription.count({
        where: { stripeSubscriptionId: ownerSubscription },
      })).toBe(1);
    },
  );
});
