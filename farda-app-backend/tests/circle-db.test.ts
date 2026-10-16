import { randomUUID } from "node:crypto";
import { PrismaPg } from "@prisma/adapter-pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { PrismaClient } from "../generated/prisma/client";
import { CircleService } from "../src/circle/service";

// CI supplies a disposable database with all migrations applied. This suite
// never falls back to DATABASE_URL and deletes only its own synthetic users.
const databaseUrl = process.env.TEST_DATABASE_URL;
describe.skipIf(!databaseUrl)("Circle PostgreSQL access boundaries", () => {
  let db: PrismaClient;
  let circle: CircleService;
  const prefix = `circle-it-${randomUUID()}`;
  const ownerId = `${prefix}-owner`;
  const recipientId = `${prefix}-recipient`;
  const otherId = `${prefix}-other`;
  const prescriptionId = `${prefix}-rx`;
  const scheduleId = `${prefix}-schedule`;
  const phoneTail = String(Number.parseInt(randomUUID().replaceAll("-", "").slice(0, 8), 16)).padStart(10, "0").slice(-7);
  const recipientPhone = `+1555${phoneTail}`;
  const otherPhone = `+1666${phoneTail}`;
  const now = new Date("2026-10-16T12:00:00.000Z");

  beforeAll(async () => {
    db = new PrismaClient({
      adapter: new PrismaPg({
        connectionString: databaseUrl!,
        max: process.env.TEST_DATABASE_SINGLE_CONNECTION === "true" ? 1 : 4,
      }),
    });
    circle = new CircleService(db, () => now, "circle-integration-secret-at-least-32-chars");
    await db.user.createMany({
      data: [
        { id: ownerId, name: "Synthetic Owner" },
        { id: recipientId, name: "Synthetic Recipient", phoneNumber: recipientPhone, phoneNumberVerified: true },
        { id: otherId, name: "Synthetic Other", phoneNumber: otherPhone, phoneNumberVerified: true },
      ],
    });
    await db.prescription.create({
      data: {
        id: prescriptionId,
        userId: ownerId,
        medicationName: "PRIVATE MEDICATION NAME",
        dosageInstructions: "PRIVATE LABEL DIRECTIONS",
        address: "PRIVATE ADDRESS",
        contactDetails: "PRIVATE CONTACT",
      },
    });
    await db.scheduleVersion.create({
      data: {
        id: scheduleId,
        prescriptionId,
        version: 1,
        timezone: "America/New_York",
        recurrence: "daily",
        times: ["09:00"],
        startDate: now,
        durationDays: 7,
        effectiveAt: now,
      },
    });
    await db.dose.createMany({
      data: [
        {
          id: `${prefix}-visible`, userId: ownerId, prescriptionId, scheduleVersionId: scheduleId,
          scheduledFor: new Date("2026-10-16T13:00:00.000Z"), status: "taken", source: "self_report",
          takenAt: new Date("2026-10-16T13:02:00.000Z"), note: "PRIVATE NOTE", mood: "PRIVATE MOOD",
        },
        {
          id: `${prefix}-cancelled`, userId: ownerId, prescriptionId,
          scheduledFor: new Date("2026-10-16T14:00:00.000Z"), status: "cancelled", canceledAt: now,
        },
      ],
    });
  }, 30_000);

  afterAll(async () => {
    if (db) {
      await db.user.deleteMany({ where: { id: { in: [ownerId, recipientId, otherId] } } });
      await db.$disconnect();
    }
  });

  it("binds acceptance to the verified recipient and consumes the code once", async () => {
    const created = await circle.invite(ownerId, recipientPhone, { doseStatus: true, reminders: true });
    await expect(circle.accept(otherId, created.invitation.id, created.invitation.inviteCode)).rejects.toMatchObject({ status: 404 });
    const accepted = await circle.accept(recipientId, created.invitation.id, created.invitation.inviteCode);
    expect(accepted).toMatchObject({ status: "accepted", permissions: { doseStatus: true, reminders: true } });
    await expect(circle.accept(recipientId, created.invitation.id, created.invitation.inviteCode)).rejects.toMatchObject({ status: 404 });
    expect(await db.circleGrant.count({ where: { ownerId, recipientId } })).toBe(1);
  });

  it("returns only the fields allowed by each live permission scope", async () => {
    const grant = await db.circleGrant.findUniqueOrThrow({ where: { ownerId_recipientId: { ownerId, recipientId } } });
    await circle.update(ownerId, grant.id, { doseStatus: true, reminders: false });
    const statusOnly = await circle.routine(recipientId, grant.id, new Date("2026-10-16T00:00:00Z"), new Date("2026-10-17T00:00:00Z"));
    expect(statusOnly.items).toHaveLength(1);
    expect(statusOnly.items[0]).toMatchObject({ label: "Routine item", state: "taken", evidence: "self_report" });
    expect(statusOnly.items[0]).not.toHaveProperty("scheduledFor");
    expect(JSON.stringify(statusOnly)).not.toMatch(/PRIVATE|medicationName|dosageInstructions|address|contactDetails|note|mood/);

    await circle.update(ownerId, grant.id, { doseStatus: false, reminders: true });
    const remindersOnly = await circle.routine(recipientId, grant.id, new Date("2026-10-16T00:00:00Z"), new Date("2026-10-17T00:00:00Z"));
    expect(remindersOnly.items).toHaveLength(1);
    expect(remindersOnly.items[0]).toMatchObject({ label: "Routine item", ownerTimeZone: "America/New_York" });
    expect(remindersOnly.items[0]).toHaveProperty("scheduledFor");
    expect(remindersOnly.items[0]).not.toHaveProperty("state");
    expect(remindersOnly.notice).toMatch(/plans, not delivery confirmations/i);
  });

  it("invalidates pending wider permissions when access is narrowed", async () => {
    const grant = await db.circleGrant.findUniqueOrThrow({ where: { ownerId_recipientId: { ownerId, recipientId } } });
    await circle.invite(ownerId, recipientPhone, { doseStatus: true, reminders: true });
    expect(await db.circleInvitation.count({ where: { ownerId } })).toBe(1);
    await circle.update(ownerId, grant.id, { doseStatus: true, reminders: false });
    expect(await db.circleInvitation.count({ where: { ownerId } })).toBe(0);
  });

  it("revocation blocks routine reads and cannot be undone by replay", async () => {
    const invite = await circle.invite(ownerId, recipientPhone, { doseStatus: true, reminders: true });
    const accepted = await circle.accept(recipientId, invite.invitation.id, invite.invitation.inviteCode);
    await circle.remove(ownerId, accepted.memberId);
    await expect(circle.routine(recipientId, accepted.memberId, new Date("2026-10-16"), new Date("2026-10-17"))).rejects.toMatchObject({ status: 404 });
    await expect(circle.accept(recipientId, invite.invitation.id, invite.invitation.inviteCode)).rejects.toMatchObject({ status: 404 });
    expect(await db.circleGrant.count({ where: { ownerId, recipientId } })).toBe(0);
  });

  it("leaving also removes a pending invitation that could restore access", async () => {
    const invite = await circle.invite(ownerId, recipientPhone, { doseStatus: true, reminders: true });
    const accepted = await circle.accept(recipientId, invite.invitation.id, invite.invitation.inviteCode);
    await circle.invite(ownerId, recipientPhone, { doseStatus: true, reminders: true });
    await circle.leave(recipientId, accepted.memberId);
    expect(await db.circleInvitation.count({ where: { ownerId } })).toBe(0);
    expect(await db.circleGrant.count({ where: { ownerId, recipientId } })).toBe(0);
  });
});
