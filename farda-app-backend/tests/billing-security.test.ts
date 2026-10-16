import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { BillingService } from "../src/billing/service";

type Row = {
  userId: string;
  stripeSubscriptionId: string;
  stripeCustomerId: string;
  priceId: string;
  tier: string;
  status: string;
  lastEventCreatedAt: Date;
  currentPeriodEnd?: Date | null;
  cancelAtPeriodEnd?: boolean;
};

const subscription = (overrides: Record<string, unknown> = {}) => ({
  id: "sub_owner",
  customer: "cus_owner",
  livemode: false,
  status: "active",
  cancel_at_period_end: false,
  items: {
    data: [{ price: { id: "price_family" }, current_period_end: 2_000_000_000 }],
  },
  ...overrides,
});

function fixture() {
  const rows = new Map<string, Row>();
  const events = new Set<string>();
  const customers = new Map([
    ["cus_owner", { userId: "owner", stripeCustomerId: "cus_owner" }],
    ["cus_other", { userId: "other", stripeCustomerId: "cus_other" }],
  ]);
  const db: any = {
    billingCustomer: {
      findUnique: vi.fn(async ({ where }: any) =>
        where.stripeCustomerId
          ? customers.get(where.stripeCustomerId)
          : [...customers.values()].find((row) => row.userId === where.userId),
      ),
      create: vi.fn(),
    },
    billingSubscription: {
      findFirst: vi.fn(async ({ where }: any) =>
        [...rows.values()].find(
          (row) =>
            row.userId === where.userId &&
            (!where.status || where.status.in.includes(row.status)),
        ),
      ),
      findUnique: vi.fn(async ({ where }: any) =>
        rows.get(where.stripeSubscriptionId),
      ),
      create: vi.fn(async ({ data }: any) => {
        if (rows.has(data.stripeSubscriptionId)) throw new Error("unique");
        rows.set(data.stripeSubscriptionId, data);
        return data;
      }),
      updateMany: vi.fn(async ({ where, data }: any) => {
        const row = rows.get(where.stripeSubscriptionId);
        const ceiling =
          where.lastEventCreatedAt?.lte ?? where.lastEventCreatedAt?.lt;
        if (
          !row ||
          row.userId !== where.userId ||
          (ceiling && row.lastEventCreatedAt > ceiling)
        )
          return { count: 0 };
        rows.set(row.stripeSubscriptionId, { ...row, ...data });
        return { count: 1 };
      }),
    },
    billingWebhookEvent: {
      findUnique: vi.fn(async ({ where }: any) =>
        events.has(where.stripeEventId) ? { stripeEventId: where.stripeEventId } : null,
      ),
      create: vi.fn(async ({ data }: any) => {
        if (events.has(data.stripeEventId)) throw new Error("unique");
        events.add(data.stripeEventId);
        return data;
      }),
    },
  };
  const stripe: any = {
    event: undefined,
    canonical: undefined,
    webhooks: {
      constructEvent: vi.fn((_raw: Buffer, signature: string) => {
        if (signature !== "valid") throw new Error("bad signature");
        return stripe.event;
      }),
    },
    subscriptions: {
      retrieve: vi.fn(async () => stripe.canonical),
    },
  };
  return { db, events, rows, service: new BillingService(db, stripe), stripe };
}

const originalEnv = { ...process.env };
beforeEach(() => {
  process.env.STRIPE_BILLING_ENABLED = "true";
  process.env.STRIPE_WEBHOOK_SECRET = "whsec_test";
  process.env.STRIPE_MODE = "test";
  process.env.STRIPE_PRICE_FAMILY_MONTHLY = "price_family";
});
afterEach(() => {
  process.env = { ...originalEnv };
});

describe("billing webhook security boundaries", () => {
  it("uses Stripe's canonical subscription rather than stale delivered state", async () => {
    const f = fixture();
    f.stripe.event = {
      id: "evt_stale",
      created: 200,
      livemode: false,
      type: "customer.subscription.updated",
      data: { object: subscription({ status: "canceled" }) },
    };
    f.stripe.canonical = subscription({ status: "active" });

    await f.service.webhook(Buffer.from("{}"), "valid");

    expect(f.stripe.subscriptions.retrieve).toHaveBeenCalledWith("sub_owner");
    expect(f.rows.get("sub_owner")).toMatchObject({
      userId: "owner",
      status: "active",
      tier: "family",
    });
  });

  it("applies canonical state even when the triggering delivery is older than the local row", async () => {
    const f = fixture();
    f.rows.set("sub_owner", {
      userId: "owner",
      stripeSubscriptionId: "sub_owner",
      stripeCustomerId: "cus_owner",
      priceId: "price_family",
      tier: "family",
      status: "active",
      lastEventCreatedAt: new Date(200_000),
    });
    f.stripe.event = {
      id: "evt_delayed_old_delivery",
      created: 100,
      livemode: false,
      type: "customer.subscription.updated",
      data: { object: subscription({ status: "active" }) },
    };
    f.stripe.canonical = subscription({ status: "canceled" });

    await f.service.webhook(Buffer.from("{}"), "valid");

    expect(f.rows.get("sub_owner")?.status).toBe("canceled");
  });

  it("applies a terminal deletion created in the same second as the current row", async () => {
    const f = fixture();
    f.rows.set("sub_owner", {
      userId: "owner",
      stripeSubscriptionId: "sub_owner",
      stripeCustomerId: "cus_owner",
      priceId: "price_family",
      tier: "family",
      status: "active",
      lastEventCreatedAt: new Date(200_000),
    });
    f.stripe.event = {
      id: "evt_deleted",
      created: 200,
      livemode: false,
      type: "customer.subscription.deleted",
      data: { object: subscription({ status: "canceled" }) },
    };

    await f.service.webhook(Buffer.from("{}"), "valid");

    expect(f.stripe.subscriptions.retrieve).not.toHaveBeenCalled();
    expect(f.rows.get("sub_owner")?.status).toBe("canceled");
  });

  it("fails closed when canonical state moves an existing subscription to an unknown price", async () => {
    const f = fixture();
    f.rows.set("sub_owner", {
      userId: "owner",
      stripeSubscriptionId: "sub_owner",
      stripeCustomerId: "cus_owner",
      priceId: "price_family",
      tier: "family",
      status: "active",
      lastEventCreatedAt: new Date(100_000),
    });
    f.stripe.event = {
      id: "evt_unknown_price",
      created: 201,
      livemode: false,
      type: "customer.subscription.updated",
      data: { object: subscription() },
    };
    f.stripe.canonical = subscription({
      items: { data: [{ price: { id: "price_attacker" } }] },
    });

    await f.service.webhook(Buffer.from("{}"), "valid");

    expect(f.rows.get("sub_owner")).toMatchObject({
      tier: "none",
      priceId: "price_attacker",
    });
  });

  it("does not transfer a known subscription id to another stored customer", async () => {
    const f = fixture();
    f.rows.set("sub_owner", {
      userId: "owner",
      stripeSubscriptionId: "sub_owner",
      stripeCustomerId: "cus_owner",
      priceId: "price_family",
      tier: "family",
      status: "active",
      lastEventCreatedAt: new Date(100_000),
    });
    f.stripe.event = {
      id: "evt_customer_collision",
      created: 201,
      livemode: false,
      type: "customer.subscription.updated",
      data: { object: subscription() },
    };
    f.stripe.canonical = subscription({ customer: "cus_other", status: "canceled" });

    await f.service.webhook(Buffer.from("{}"), "valid");

    expect(f.rows.get("sub_owner")).toMatchObject({
      userId: "owner",
      stripeCustomerId: "cus_owner",
      status: "active",
    });
    expect(f.db.billingSubscription.updateMany).not.toHaveBeenCalled();
  });

  it("does not ledger an event when canonical retrieval fails", async () => {
    const f = fixture();
    f.stripe.event = {
      id: "evt_provider_failure",
      created: 202,
      livemode: false,
      type: "customer.subscription.updated",
      data: { object: subscription() },
    };
    f.stripe.subscriptions.retrieve.mockRejectedValueOnce(
      new Error("Stripe unavailable"),
    );

    await expect(
      f.service.webhook(Buffer.from("{}"), "valid"),
    ).rejects.toThrow("Stripe unavailable");
    expect(f.events.has("evt_provider_failure")).toBe(false);
  });

  it("rejects a signed event from the wrong Stripe mode before provider or database mutation", async () => {
    const f = fixture();
    process.env.STRIPE_MODE = "live";
    f.stripe.event = {
      id: "evt_test_into_live",
      created: 203,
      livemode: false,
      type: "customer.subscription.updated",
      data: { object: subscription() },
    };

    await expect(
      f.service.webhook(Buffer.from("{}"), "valid"),
    ).rejects.toMatchObject({ code: "mode_mismatch" });
    expect(f.stripe.subscriptions.retrieve).not.toHaveBeenCalled();
    expect(f.db.billingSubscription.create).not.toHaveBeenCalled();
    expect(f.db.billingWebhookEvent.create).not.toHaveBeenCalled();
  });

  it("rejects canonical subscription state from the wrong Stripe mode", async () => {
    const f = fixture();
    f.stripe.event = {
      id: "evt_canonical_mode",
      created: 204,
      livemode: false,
      type: "customer.subscription.updated",
      data: { object: subscription() },
    };
    f.stripe.canonical = subscription({ livemode: true });

    await expect(
      f.service.webhook(Buffer.from("{}"), "valid"),
    ).rejects.toMatchObject({ code: "mode_mismatch" });
    expect(f.db.billingSubscription.create).not.toHaveBeenCalled();
    expect(f.db.billingWebhookEvent.create).not.toHaveBeenCalled();
  });
});
