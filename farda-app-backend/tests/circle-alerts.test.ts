import { describe, expect, it, vi } from "vitest";
import type { PrismaClient } from "../generated/prisma/client";
import { CircleAlertService, CIRCLE_ALERT_NOTICE } from "../src/circle/alerts";

const grant = { id: "grant-1", ownerId: "owner", recipientId: "recipient", shareDoseStatus: true };
const policy = { grantId: grant.id, enabled: true, recipientConsented: true, gracePeriodMinutes: 30, quietHoursStart: "01:00", quietHoursEnd: "02:00", timeZone: "America/New_York", updatedAt: new Date(), grant };
const dose = { id: "dose-1", scheduledFor: new Date("2026-11-01T04:00:00Z") };

function workerDb(now: Date, overrides: { liveGrant?: unknown; createCounts?: number[] } = {}) {
  const counts = [...(overrides.createCounts ?? [1])];
  const tx: any = {
    $queryRaw: vi.fn(async () => []),
    circleGrant: { findFirst: vi.fn(async () => overrides.liveGrant === undefined ? { ...grant, alertPolicy: policy } : overrides.liveGrant) },
    dose: { findFirst: vi.fn(async () => dose) },
    billingSubscription: { findFirst: vi.fn(async () => ({ id: "sub" })) },
    circleAlert: { createMany: vi.fn(async () => ({ count: counts.shift() ?? 0 })) },
  };
  const db: any = {
    circleAlertPolicy: { findMany: vi.fn(async () => [policy]), updateMany: vi.fn(async () => ({ count: 1 })) },
    billingSubscription: { findFirst: vi.fn(async () => ({ id: "sub" })) },
    dose: { findMany: vi.fn(async () => [dose]) },
    $transaction: (fn: (value: unknown) => unknown) => fn(tx),
  };
  return { service: new CircleAlertService(db as PrismaClient, () => now), db, tx };
}

describe("Circle alert policy and materialization", () => {
  it.each([
    new Date("2026-11-01T05:30:00Z"), // 01:30 EDT, before the fall-back
    new Date("2026-11-01T06:30:00Z"), // 01:30 EST, after the fall-back
  ])("defers during both instances of a repeated DST quiet-hour clock time", async now => {
    const { service, db, tx } = workerDb(now);
    await expect(service.materialize()).resolves.toMatchObject({ created: 0 });
    expect(db.dose.findMany).not.toHaveBeenCalled();
    expect(tx.circleAlert.createMany).not.toHaveBeenCalled();
  });

  it("rechecks the live grant inside the write transaction", async () => {
    const { service, tx } = workerDb(new Date("2026-11-01T08:00:00Z"), { liveGrant: null });
    await expect(service.materialize()).resolves.toMatchObject({ created: 0 });
    expect(tx.circleAlert.createMany).not.toHaveBeenCalled();
  });

  it("uses the unique create as an idempotency boundary", async () => {
    const { service, tx } = workerDb(new Date("2026-11-01T08:00:00Z"), { createCounts: [1, 0] });
    await expect(service.materialize()).resolves.toMatchObject({ created: 1 });
    await expect(service.materialize()).resolves.toMatchObject({ created: 0 });
    expect(tx.circleAlert.createMany).toHaveBeenCalledWith(expect.objectContaining({ skipDuplicates: true }));
  });

  it("bounds candidates to the grace window and the preceding 24 hours", async () => {
    const now = new Date("2026-11-01T08:00:00Z");
    const { service, db } = workerDb(now);
    await service.materialize();
    expect(db.dose.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ scheduledFor: { gt: new Date("2026-10-31T08:00:00Z"), lte: new Date("2026-11-01T07:30:00Z") } }), take: 25 }));
  });

  it("advances a durable evaluation cursor so policies beyond the batch are reached", async () => {
    const now = new Date("2026-11-01T08:00:00Z");
    const { service, db } = workerDb(now);
    const p = (grantId: string) => ({ ...policy, grantId, grant: { ...grant, id: grantId } });
    db.circleAlertPolicy.findMany.mockResolvedValueOnce([p("g1"), p("g2")]).mockResolvedValueOnce([p("g3"), p("g1")]);
    db.dose.findMany.mockResolvedValue([]);
    await service.materialize(2);
    await service.materialize(2);
    expect(db.circleAlertPolicy.findMany).toHaveBeenCalledWith(expect.objectContaining({ orderBy: [{ lastEvaluatedAt: { sort: "asc", nulls: "first" } }, { grantId: "asc" }], take: 2 }));
    expect(db.circleAlertPolicy.updateMany).toHaveBeenCalledWith({ where: { grantId: "g3" }, data: { lastEvaluatedAt: now } });
  });
});

describe("Circle alert inbox privacy", () => {
  it("cancels a resolved alert before returning the inbox", async () => {
    const db: any = {
      circleAlert: {
        findMany: vi.fn()
          .mockResolvedValueOnce([{ id: "alert", ownerId: "owner", grant: { ...grant, alertPolicy: policy }, dose: { status: "taken", takenAt: new Date(), canceledAt: null, snoozedUntil: null, prescription: { archivedAt: null } } }])
          .mockResolvedValueOnce([]),
        updateMany: vi.fn(async () => ({ count: 1 })),
      },
      billingSubscription: { findFirst: vi.fn(async () => ({ id: "sub" })) },
    };
    await expect(new CircleAlertService(db as PrismaClient).inbox("recipient")).resolves.toEqual({ alerts: [], notice: CIRCLE_ALERT_NOTICE });
    expect(db.circleAlert.updateMany).toHaveBeenCalledWith(expect.objectContaining({ data: { state: "cancelled", cancelReason: "occurrence_resolved" } }));
  });

  it("cancels access after family entitlement is lost", async () => {
    const db: any = {
      circleAlert: {
        findMany: vi.fn().mockResolvedValueOnce([{ id: "alert", ownerId: "owner", grant: { ...grant, alertPolicy: policy }, dose: { status: "unconfirmed", takenAt: null, canceledAt: null, snoozedUntil: null, prescription: { archivedAt: null } } }]).mockResolvedValueOnce([]),
        updateMany: vi.fn(async () => ({ count: 1 })),
      },
      billingSubscription: { findFirst: vi.fn(async () => null) },
    };
    await new CircleAlertService(db as PrismaClient).inbox("recipient");
    expect(db.circleAlert.updateMany).toHaveBeenCalledWith(expect.objectContaining({ data: { state: "cancelled", cancelReason: "entitlement_lost" } }));
  });

  it("omits the scheduled time without reminder sharing permission", async () => {
    const createdAt = new Date("2026-11-01T08:00:00Z");
    const db: any = {
      circleAlert: { findMany: vi.fn().mockResolvedValueOnce([]).mockResolvedValueOnce([{ id: "alert", grantId: "grant-1", doseId: "dose-1", scheduledFor: createdAt, createdAt, readAt: null, owner: { id: "owner", name: "Alex" }, grant: { shareReminders: false } }]) },
    };
    const result = await new CircleAlertService(db as PrismaClient, () => createdAt).inbox("recipient");
    expect(result.alerts[0]).toMatchObject({ scheduledFor: null });
  });
});
