import { randomUUID } from "node:crypto";
import { PrismaPg } from "@prisma/adapter-pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { PrismaClient } from "../generated/prisma/client";
import { CircleAlertService } from "../src/circle/alerts";

// CI supplies a disposable database with all migrations applied. Never fall
// back to DATABASE_URL, since these tests create and delete relational data.
const databaseUrl = process.env.TEST_DATABASE_URL;
describe.skipIf(!databaseUrl)("Circle alerts PostgreSQL integration", () => {
  let db: PrismaClient;
  const prefix = `circle-alert-it-${randomUUID()}`;
  const ownerId = `${prefix}-owner`, recipientId = `${prefix}-recipient`, prescriptionId = `${prefix}-rx`;
  const now = new Date();
  let grantId: string;

  beforeAll(async () => {
    db = new PrismaClient({ adapter: new PrismaPg({ connectionString: databaseUrl!, max: process.env.TEST_DATABASE_SINGLE_CONNECTION === "true" ? 1 : 4 }) });
    await db.user.createMany({ data: [{ id: ownerId, name: "Owner" }, { id: recipientId, name: "Recipient" }] });
    await db.billingSubscription.create({ data: { userId: ownerId, stripeSubscriptionId: `${prefix}-sub`, stripeCustomerId: `${prefix}-cus`, priceId: `${prefix}-price`, tier: "family", status: "active", currentPeriodEnd: new Date(now.getTime() + 86_400_000), lastEventCreatedAt: now } });
    await db.prescription.create({ data: { id: prescriptionId, userId: ownerId, medicationName: "PRIVATE MEDICATION" } });
    const grant = await db.circleGrant.create({ data: { ownerId, recipientId, shareDoseStatus: true, shareReminders: false } });
    grantId = grant.id;
    const hour = now.getUTCHours();
    await db.circleAlertPolicy.create({ data: { grantId, enabled: true, recipientConsented: true, gracePeriodMinutes: 15, timeZone: "UTC", quietHoursStart: `${String((hour + 2) % 24).padStart(2, "0")}:00`, quietHoursEnd: `${String((hour + 3) % 24).padStart(2, "0")}:00` } });
    await db.dose.create({ data: { id: `${prefix}-dose`, userId: ownerId, prescriptionId, scheduledFor: new Date(now.getTime() - 60 * 60_000) } });
  }, 30_000);

  afterAll(async () => {
    if (db) { await db.user.deleteMany({ where: { id: { in: [ownerId, recipientId] } } }); await db.$disconnect(); }
  });

  it("materializes once through real locks and hides time without reminder permission", async () => {
    const service = new CircleAlertService(db, () => now);
    await expect(service.materialize(20)).resolves.toMatchObject({ created: 1 });
    await expect(service.materialize(20)).resolves.toMatchObject({ created: 0 });
    const inbox = await service.inbox(recipientId);
    expect(inbox.alerts).toHaveLength(1);
    expect(inbox.alerts[0]).toMatchObject({ grantId, scheduledFor: null, kind: "confirmation_not_recorded" });
    expect(JSON.stringify(inbox)).not.toContain("PRIVATE MEDICATION");
  });

  it("fails closed when the paid period expires even if status remains active", async () => {
    await db.billingSubscription.updateMany({ where: { userId: ownerId }, data: { currentPeriodEnd: new Date(now.getTime() - 1) } });
    const service = new CircleAlertService(db, () => now);
    await expect(service.inbox(recipientId)).resolves.toMatchObject({ alerts: [] });
    expect(await db.circleAlert.count({ where: { grantId, state: "active" } })).toBe(0);
  });

  it("revocation cascades alerts and prevents subsequent reads", async () => {
    await db.circleGrant.delete({ where: { id: grantId } });
    expect(await db.circleAlert.count({ where: { grantId } })).toBe(0);
    await expect(new CircleAlertService(db, () => now).inbox(recipientId)).resolves.toMatchObject({ alerts: [] });
  });
});
