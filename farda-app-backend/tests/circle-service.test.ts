import { describe, expect, it, vi } from "vitest";
import type { PrismaClient } from "../generated/prisma/client";
import { CircleService, resolvePhoneHashSecret } from "../src/circle/service";

const now = new Date("2026-10-16T12:00:00Z");

describe("Circle account and permission boundaries", () => {
  it("fails closed without a strong production phone hashing secret", () => {
    expect(() => resolvePhoneHashSecret({ NODE_ENV: "production" } as NodeJS.ProcessEnv)).toThrow(/phone hash secret/);
    expect(resolvePhoneHashSecret({ NODE_ENV: "production", BETTER_AUTH_SECRET: "x".repeat(32) } as NodeJS.ProcessEnv)).toHaveLength(32);
  });
  it("does not reveal or accept an invitation for a different verified phone", async () => {
    const db = {
      user: { findUnique: vi.fn(async () => ({ id: "recipient-b", phoneNumber: "+15550000002", phoneNumberVerified: true })) },
      circleInvitation: { findFirst: vi.fn(async () => null) },
    } as unknown as PrismaClient;
    const service = new CircleService(db, () => now);
    await expect(service.accept("recipient-b", "invite-a", "a".repeat(32))).rejects.toMatchObject({ status: 404 });
    expect((db as any).circleInvitation.findFirst).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ id: "invite-a", recipientPhoneHash: expect.stringMatching(/^[a-f0-9]{64}$/), OR: [{ recipientId: "recipient-b" }, { recipientId: null }] }) }));
  });

  it("rechecks the live grant and only returns fields currently permitted", async () => {
    const grant = { id: "grant-1", ownerId: "owner", recipientId: "recipient", shareDoseStatus: true, shareReminders: false, owner: { id: "owner", name: "Alex" } };
    const tx = {
      $queryRaw: vi.fn(async () => [{ id: "grant-1" }]),
      circleGrant: { findFirst: vi.fn(async () => grant) },
      dose: { findMany: vi.fn(async () => [
        { id: "dose-1", scheduledFor: now, snoozedUntil: null, status: "taken", source: "self_report", takenAt: now, updatedAt: now, scheduleVersion: { timezone: "America/New_York" } },
        { id: "dose-2", scheduledFor: now, snoozedUntil: null, status: "skipped", source: "self_report", takenAt: null, updatedAt: new Date("2026-10-16T12:05:00Z"), scheduleVersion: { timezone: "America/New_York" } },
        { id: "dose-3", scheduledFor: now, snoozedUntil: null, status: "taken", source: "schedule", takenAt: now, updatedAt: now, scheduleVersion: { timezone: "America/New_York" } },
        { id: "dose-4", scheduledFor: now, snoozedUntil: null, status: "unconfirmed", source: "self_report", takenAt: null, updatedAt: now, scheduleVersion: { timezone: "America/New_York" } },
      ]) },
    };
    const db = { $transaction: (fn: (value: typeof tx) => unknown) => fn(tx) } as unknown as PrismaClient;
    const result = await new CircleService(db, () => now).routine("recipient", "grant-1", new Date("2026-10-16"), new Date("2026-10-17"));
    expect(result.items).toEqual([
      { id: "dose-1", label: "Routine item", state: "taken", evidence: "self_report", recordedAt: now },
      { id: "dose-2", label: "Routine item", state: "skipped", evidence: "self_report", recordedAt: new Date("2026-10-16T12:05:00Z") },
      { id: "dose-3", label: "Routine item", state: "taken", evidence: "none", recordedAt: now },
      { id: "dose-4", label: "Routine item", state: "not_recorded", evidence: "none", recordedAt: null },
    ]);
    expect(result.items[0]).not.toHaveProperty("scheduledFor");
    expect(result.items[0]).not.toHaveProperty("prescriptionName");
    expect(tx.dose.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ canceledAt: null, status: { not: "cancelled" } }) }));
  });

  it("returns no stale routine after access is revoked", async () => {
    const tx = { $queryRaw: vi.fn(async () => []), circleGrant: { findFirst: vi.fn(async () => null) }, dose: { findMany: vi.fn() } };
    const db = { $transaction: (fn: (value: typeof tx) => unknown) => fn(tx) } as unknown as PrismaClient;
    await expect(new CircleService(db, () => now).routine("recipient", "revoked", new Date("2026-10-16"), new Date("2026-10-17"))).rejects.toMatchObject({ status: 404 });
    expect(tx.dose.findMany).not.toHaveBeenCalled();
  });

  it("revocation also invalidates pending invitations that could restore access", async () => {
    const tx = {
      circleGrant: { findFirst: vi.fn(async () => ({ id: "grant-1", recipient: { phoneNumber: "+15550000002" } })), deleteMany: vi.fn(async () => ({ count: 1 })) },
      circleInvitation: { deleteMany: vi.fn(async () => ({ count: 1 })) },
    };
    const db = { $transaction: (fn: (value: typeof tx) => unknown) => fn(tx) } as unknown as PrismaClient;
    await expect(new CircleService(db, () => now).remove("owner", "grant-1")).resolves.toEqual({ status: "revoked" });
    expect(tx.circleInvitation.deleteMany).toHaveBeenCalledWith({ where: { ownerId: "owner", recipientPhoneHash: expect.stringMatching(/^[a-f0-9]{64}$/) } });
  });
});
