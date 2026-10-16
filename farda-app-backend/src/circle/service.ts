import { createHash, createHmac, randomBytes } from "node:crypto";
import { Prisma, type PrismaClient } from "../../generated/prisma/client";
import { ConsumerError } from "../reminders/policy";

export type CirclePermissions = { doseStatus: boolean; reminders: boolean };
const digest = (value: string) => createHash("sha256").update(value).digest("hex");
export function resolvePhoneHashSecret(env = process.env) {
  const secret = env.CIRCLE_PHONE_HASH_SECRET || env.BETTER_AUTH_SECRET;
  if (secret && secret.length >= 32) return secret;
  if (env.NODE_ENV === "production") throw new Error("Production Circle sharing requires a strong phone hash secret");
  return "development-circle-phone-hash-secret";
}
const person = (user: { id: string; name: string | null }) => ({
  id: user.id,
  displayName: user.name?.trim() || "Circle member",
});

export class CircleService {
  constructor(private readonly db: PrismaClient, private readonly now = () => new Date(), private readonly phoneHashSecret = resolvePhoneHashSecret()) {}
  private phoneDigest(value: string) { return createHmac("sha256", this.phoneHashSecret).update(`circle-phone:v1:${value}`).digest("hex"); }

  async overview(ownerId: string) {
    const [pending, members] = await Promise.all([
      this.db.circleInvitation.findMany({ where: { ownerId, expiresAt: { gt: this.now() } }, orderBy: { createdAt: "desc" } }),
      this.db.circleGrant.findMany({ where: { ownerId }, include: { recipient: { select: { id: true, name: true } } }, orderBy: { acceptedAt: "desc" } }),
    ]);
    return {
      pending: pending.map(i => ({ id: i.id, person: { id: "", displayName: `Phone ending ${i.recipientPhoneLast4}` }, permissions: { doseStatus: i.shareDoseStatus, reminders: i.shareReminders }, createdAt: i.createdAt, expiresAt: i.expiresAt })),
      members: members.map(g => ({ id: g.id, person: person(g.recipient), permissions: { doseStatus: g.shareDoseStatus, reminders: g.shareReminders }, acceptedAt: g.acceptedAt, updatedAt: g.updatedAt })),
    };
  }

  async invite(ownerId: string, recipientPhone: string, permissions: CirclePermissions) {
    if (!/^\+[1-9]\d{7,14}$/.test(recipientPhone)) throw new ConsumerError(400, "Enter a complete phone number including country code.");
    const owner = await this.db.user.findUnique({ where: { id: ownerId } });
    if (!owner) throw new ConsumerError(401, "Sign in to continue.");
    const phoneHash = this.phoneDigest(recipientPhone);
    if (owner.phoneNumber && this.phoneDigest(owner.phoneNumber) === phoneHash) throw new ConsumerError(400, "Choose a different person.");
    const recipient = await this.db.user.findUnique({ where: { phoneNumber: recipientPhone } });
    const secret = randomBytes(24).toString("base64url");
    const data = { recipientId: recipient?.id, recipientPhoneLast4: recipientPhone.slice(-4), secretHash: digest(secret), shareDoseStatus: permissions.doseStatus, shareReminders: permissions.reminders, expiresAt: new Date(this.now().getTime() + 7 * 86_400_000) };
    const invitation = await this.db.circleInvitation.upsert({ where: { ownerId_recipientPhoneHash: { ownerId, recipientPhoneHash: phoneHash } }, create: { ownerId, recipientPhoneHash: phoneHash, ...data }, update: data });
    return { status: "awaiting_acceptance", invitation: { id: invitation.id, person: { id: "", displayName: `Phone ending ${invitation.recipientPhoneLast4}` }, inviteCode: secret, createdAt: invitation.createdAt, expiresAt: invitation.expiresAt, permissions } };
  }

  async received(userId: string) {
    const user = await this.db.user.findUnique({ where: { id: userId } });
    if (!user?.phoneNumber || !user.phoneNumberVerified) return { invitations: [] };
    const invitations = await this.db.circleInvitation.findMany({ where: { recipientPhoneHash: this.phoneDigest(user.phoneNumber), OR: [{ recipientId: userId }, { recipientId: null }], expiresAt: { gt: this.now() } }, include: { owner: { select: { id: true, name: true } } }, orderBy: { createdAt: "desc" } });
    return { invitations: invitations.map(i => ({ id: i.id, person: person(i.owner), permissions: { doseStatus: i.shareDoseStatus, reminders: i.shareReminders }, createdAt: i.createdAt, expiresAt: i.expiresAt })) };
  }

  async accept(userId: string, invitationId: string, inviteCode: string) {
    const user = await this.db.user.findUnique({ where: { id: userId } });
    if (!user?.phoneNumber || !user.phoneNumberVerified) throw new ConsumerError(404, "Invitation expired or unavailable.");
    const invitation = await this.db.circleInvitation.findFirst({ where: { id: invitationId, recipientPhoneHash: this.phoneDigest(user.phoneNumber), OR: [{ recipientId: userId }, { recipientId: null }], secretHash: digest(inviteCode), expiresAt: { gt: this.now() } } });
    if (!invitation) throw new ConsumerError(404, "Invitation expired or unavailable.");
    if (invitation.ownerId === userId) throw new ConsumerError(400, "You cannot join your own Circle.");
    const grant = await this.db.$transaction(async tx => {
      const claimed = await tx.circleInvitation.deleteMany({ where: { id: invitation.id, ownerId: invitation.ownerId, recipientPhoneHash: invitation.recipientPhoneHash, secretHash: invitation.secretHash, expiresAt: { gt: this.now() } } });
      if (claimed.count !== 1) throw new ConsumerError(409, "Invitation changed. Ask for a new invitation.");
      return tx.circleGrant.upsert({ where: { ownerId_recipientId: { ownerId: invitation.ownerId, recipientId: userId } }, create: { ownerId: invitation.ownerId, recipientId: userId, shareDoseStatus: invitation.shareDoseStatus, shareReminders: invitation.shareReminders }, update: { shareDoseStatus: invitation.shareDoseStatus, shareReminders: invitation.shareReminders, acceptedAt: this.now() } });
    });
    return { status: "accepted", memberId: grant.id, permissions: { doseStatus: grant.shareDoseStatus, reminders: grant.shareReminders } };
  }

  async update(ownerId: string, grantId: string, permissions: CirclePermissions) {
    await this.db.$transaction(async tx => {
      const grant = await tx.circleGrant.findFirst({ where: { id: grantId, ownerId }, include: { recipient: { select: { phoneNumber: true } } } });
      if (!grant) throw new ConsumerError(404, "Circle member not found.");
      if (grant.recipient.phoneNumber) await tx.circleInvitation.deleteMany({ where: { ownerId, recipientPhoneHash: this.phoneDigest(grant.recipient.phoneNumber) } });
      const updated = await tx.circleGrant.updateMany({ where: { id: grantId, ownerId }, data: { shareDoseStatus: permissions.doseStatus, shareReminders: permissions.reminders } });
      if (updated.count !== 1) throw new ConsumerError(409, "Circle membership changed. Refresh and try again.");
    });
    return { id: grantId, permissions };
  }
  async remove(ownerId: string, grantId: string) {
    await this.db.$transaction(async tx => {
      const grant = await tx.circleGrant.findFirst({ where: { id: grantId, ownerId }, include: { recipient: { select: { phoneNumber: true } } } });
      if (!grant) throw new ConsumerError(404, "Circle member not found.");
      if (grant.recipient.phoneNumber) await tx.circleInvitation.deleteMany({ where: { ownerId, recipientPhoneHash: this.phoneDigest(grant.recipient.phoneNumber) } });
      const removed = await tx.circleGrant.deleteMany({ where: { id: grantId, ownerId } });
      if (removed.count !== 1) throw new ConsumerError(409, "Circle membership changed. Refresh and try again.");
    });
    return { status: "revoked" };
  }
  async cancel(ownerId: string, invitationId: string) {
    const result = await this.db.circleInvitation.deleteMany({ where: { id: invitationId, ownerId } });
    if (result.count !== 1) throw new ConsumerError(404, "Invitation not found.");
    return { status: "cancelled" };
  }
  async decline(userId: string, invitationId: string) {
    const user = await this.db.user.findUnique({ where: { id: userId } });
    if (!user?.phoneNumber || !user.phoneNumberVerified) throw new ConsumerError(404, "Invitation not found.");
    const result = await this.db.circleInvitation.deleteMany({ where: { id: invitationId, recipientPhoneHash: this.phoneDigest(user.phoneNumber), OR: [{ recipientId: userId }, { recipientId: null }] } });
    if (result.count !== 1) throw new ConsumerError(404, "Invitation not found.");
    return { status: "declined" };
  }
  async leave(userId: string, grantId: string) {
    await this.db.$transaction(async tx => {
      const grant = await tx.circleGrant.findFirst({ where: { id: grantId, recipientId: userId } });
      const user = await tx.user.findUnique({ where: { id: userId }, select: { phoneNumber: true } });
      if (!grant) throw new ConsumerError(404, "Shared Circle not found.");
      if (user?.phoneNumber) await tx.circleInvitation.deleteMany({ where: { ownerId: grant.ownerId, recipientPhoneHash: this.phoneDigest(user.phoneNumber) } });
      const removed = await tx.circleGrant.deleteMany({ where: { id: grantId, recipientId: userId } });
      if (removed.count !== 1) throw new ConsumerError(409, "Circle membership changed. Refresh and try again.");
    });
    return { status: "left" };
  }

  async shared(userId: string) {
    const grants = await this.db.circleGrant.findMany({ where: { recipientId: userId }, include: { owner: { select: { id: true, name: true } } }, orderBy: { updatedAt: "desc" } });
    return { circles: grants.map(g => ({ access: { id: g.id, permissions: { doseStatus: g.shareDoseStatus, reminders: g.shareReminders }, acceptedAt: g.acceptedAt, updatedAt: g.updatedAt }, owner: person(g.owner) })) };
  }

  async routine(userId: string, grantId: string, from: Date, to: Date) {
    return this.db.$transaction(async tx => {
      await tx.$queryRaw(Prisma.sql`SELECT "id" FROM "CircleGrant" WHERE "id" = ${grantId} AND "recipientId" = ${userId} FOR SHARE`);
      const grant = await tx.circleGrant.findFirst({ where: { id: grantId, recipientId: userId }, include: { owner: { select: { id: true, name: true } } } });
      if (!grant) throw new ConsumerError(404, "Shared Circle not found.");
      if (!grant.shareDoseStatus && !grant.shareReminders) return { owner: person(grant.owner), permissions: { doseStatus: false, reminders: false }, items: [], fetchedAt: this.now(), notice: "Not recorded does not mean missed." };
      const doses = await tx.dose.findMany({ where: { userId: grant.ownerId, scheduledFor: { gte: from, lt: to }, canceledAt: null, status: { not: "cancelled" }, prescription: { archivedAt: null } }, select: { id: true, scheduledFor: true, snoozedUntil: true, status: true, source: true, takenAt: true, updatedAt: true, scheduleVersion: { select: { timezone: true } } }, orderBy: { scheduledFor: "asc" }, take: 500 });
      const items = doses.map(d => {
      const state = d.status === "taken" ? "taken" : d.status === "skipped" ? "skipped" : d.snoozedUntil ? "snoozed" : "not_recorded";
      return {
        id: d.id,
        label: "Routine item",
        ...(grant.shareReminders ? { scheduledFor: d.scheduledFor, snoozedUntil: d.snoozedUntil, ownerTimeZone: d.scheduleVersion?.timezone ?? "UTC" } : {}),
        ...(grant.shareDoseStatus ? {
          state,
          evidence: state === "not_recorded" ? "none" : d.source === "self_report" ? "self_report" : d.source === "device_observation" ? "device_observation" : "none",
          recordedAt: state === "not_recorded" ? null : d.takenAt ?? d.updatedAt,
        } : {}),
      };
      });
      return { owner: person(grant.owner), permissions: { doseStatus: grant.shareDoseStatus, reminders: grant.shareReminders }, items, fetchedAt: this.now(), notice: "Scheduled times are plans, not delivery confirmations. Not recorded does not mean missed." };
    });
  }
}
