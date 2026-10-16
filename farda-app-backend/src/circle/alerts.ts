import type { PrismaClient } from "../../generated/prisma/client";
import { ConsumerError, inQuietHours, validTimeZone } from "../reminders/policy";
import { hasEntitlement } from "../billing/entitlements";

export const CIRCLE_ALERT_NOTICE = "A confirmation has not been recorded. This does not mean a dose was missed.";
export const DEFAULT_CIRCLE_ALERT_POLICY = Object.freeze({
  enabled: false,
  recipientConsented: false,
  gracePeriodMinutes: 30,
  quietHoursStart: "21:00",
  quietHoursEnd: "08:00",
  timeZone: "UTC",
});

export interface CircleAlertPolicyView { enabled: boolean; recipientConsented: boolean; gracePeriodMinutes: number; quietHoursStart: string; quietHoursEnd: string; timeZone: string }
export type CircleAlertSettings = Omit<CircleAlertPolicyView, "recipientConsented">;
const activeSubscription = (now: Date) => ({ status: { in: ["active", "trialing"] }, tier: { in: ["family"] }, currentPeriodEnd: { gt: now } });
const view = (policy: CircleAlertPolicyView) => ({ policy });

function validate(settings: CircleAlertSettings) {
  if (!Number.isInteger(settings.gracePeriodMinutes) || settings.gracePeriodMinutes < 15 || settings.gracePeriodMinutes > 240)
    throw new ConsumerError(400, "Choose a grace period from 15 to 240 minutes.");
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(settings.quietHoursStart) || !/^([01]\d|2[0-3]):[0-5]\d$/.test(settings.quietHoursEnd) || !validTimeZone(settings.timeZone))
    throw new ConsumerError(400, "Choose valid quiet hours and time zone.");
}

export class CircleAlertService {
  constructor(private readonly db: PrismaClient, private readonly now = () => new Date()) {}

  private async entitled(ownerId: string, db: Pick<PrismaClient, "billingSubscription"> = this.db) {
    return hasEntitlement(db, ownerId, "family_alerts");
  }

  async ownerPolicy(ownerId: string, grantId: string) {
    const grant = await this.db.circleGrant.findFirst({ where: { id: grantId, ownerId }, include: { alertPolicy: true } });
    if (!grant) throw new ConsumerError(404, "Circle member not found.");
    return view({ ...DEFAULT_CIRCLE_ALERT_POLICY, ...grant.alertPolicy });
  }

  async saveOwnerPolicy(ownerId: string, grantId: string, settings: CircleAlertSettings) {
    validate(settings);
    if (settings.enabled && !(await this.entitled(ownerId))) throw new ConsumerError(402, "Family alerts require a Family membership.");
    const grant = await this.db.circleGrant.findFirst({ where: { id: grantId, ownerId }, select: { id: true } });
    if (!grant) throw new ConsumerError(404, "Circle member not found.");
    const policy = await this.db.circleAlertPolicy.upsert({
      where: { grantId }, create: { grantId, ...settings }, update: settings,
    });
    if (!settings.enabled) await this.db.circleAlert.updateMany({ where: { grantId, state: "active" }, data: { state: "cancelled", cancelReason: "owner_disabled" } });
    return view(policy);
  }

  async recipientPolicy(recipientId: string, grantId: string) {
    const grant = await this.db.circleGrant.findFirst({ where: { id: grantId, recipientId }, include: { alertPolicy: true } });
    if (!grant) throw new ConsumerError(404, "Shared Circle not found.");
    return view({ ...DEFAULT_CIRCLE_ALERT_POLICY, ...grant.alertPolicy });
  }

  async saveRecipientConsent(recipientId: string, grantId: string, consented: boolean) {
    const grant = await this.db.circleGrant.findFirst({ where: { id: grantId, recipientId }, select: { id: true } });
    if (!grant) throw new ConsumerError(404, "Shared Circle not found.");
    const policy = await this.db.circleAlertPolicy.upsert({ where: { grantId }, create: { grantId, recipientConsented: consented }, update: { recipientConsented: consented } });
    if (!consented) await this.db.circleAlert.updateMany({ where: { grantId, recipientId, state: "active" }, data: { state: "cancelled", cancelReason: "recipient_withdrew_consent" } });
    return view(policy);
  }

  async materialize(limit = 100) {
    const now = this.now();
    const policies = await this.db.circleAlertPolicy.findMany({
      where: { enabled: true, recipientConsented: true }, include: { grant: true }, orderBy: [{ lastEvaluatedAt: { sort: "asc", nulls: "first" } }, { grantId: "asc" }], take: Math.min(Math.max(limit, 1), 500),
    });
    let created = 0;
    for (const policy of policies) {
      await this.db.circleAlertPolicy.updateMany({ where: { grantId: policy.grantId }, data: { lastEvaluatedAt: now } });
      if (!policy.grant.shareDoseStatus || !(await this.entitled(policy.grant.ownerId))) continue;
      if (inQuietHours(now, { ...policy, callsEnabled: false, liveActivitiesEnabled: false, maxCallsPerDay: 0 })) continue;
      const cutoff = new Date(now.getTime() - policy.gracePeriodMinutes * 60_000);
      const stale = new Date(now.getTime() - 24 * 60 * 60_000);
      const doses = await this.db.dose.findMany({ where: { userId: policy.grant.ownerId, scheduledFor: { gt: stale, lte: cutoff }, status: "unconfirmed", takenAt: null, canceledAt: null, snoozedUntil: null, prescription: { archivedAt: null } }, orderBy: { scheduledFor: "asc" }, take: Math.min(25, limit - created) });
      for (const dose of doses) {
        const result = await this.db.$transaction(async tx => {
          await tx.$queryRaw`SELECT "id" FROM "CircleGrant" WHERE "id" = ${policy.grantId} FOR SHARE`;
          await tx.$queryRaw`SELECT "grantId" FROM "CircleAlertPolicy" WHERE "grantId" = ${policy.grantId} FOR SHARE`;
          await tx.$queryRaw`SELECT "id" FROM "Dose" WHERE "id" = ${dose.id} FOR SHARE`;
          await tx.$queryRaw`SELECT "id" FROM "BillingSubscription" WHERE "userId" = ${policy.grant.ownerId} AND "status" IN ('active', 'trialing') AND "tier" = 'family' AND "currentPeriodEnd" > ${now} FOR SHARE`;
          const [liveGrant, liveDose, entitled] = await Promise.all([
            tx.circleGrant.findFirst({ where: { id: policy.grantId, shareDoseStatus: true }, include: { alertPolicy: true } }),
            tx.dose.findFirst({ where: { id: dose.id, userId: policy.grant.ownerId, status: "unconfirmed", takenAt: null, canceledAt: null, snoozedUntil: null, prescription: { archivedAt: null } } }),
            this.entitled(policy.grant.ownerId, tx),
          ]);
          const livePolicy = liveGrant?.alertPolicy;
          if (!liveGrant || !livePolicy?.enabled || !livePolicy.recipientConsented || !liveDose || !entitled) return { count: 0 };
          if (liveDose.scheduledFor.getTime() > now.getTime() - livePolicy.gracePeriodMinutes * 60_000 || inQuietHours(now, { ...livePolicy, callsEnabled: false, liveActivitiesEnabled: false, maxCallsPerDay: 0 })) return { count: 0 };
          return tx.circleAlert.createMany({ data: [{ grantId: liveGrant.id, ownerId: liveGrant.ownerId, recipientId: liveGrant.recipientId, doseId: liveDose.id, scheduledFor: liveDose.scheduledFor }], skipDuplicates: true });
        });
        created += result.count;
        if (created >= limit) return { created, examinedPolicies: policies.length };
      }
    }
    return { created, examinedPolicies: policies.length };
  }

  private async cancelIneligible(recipientId: string) {
    const active = await this.db.circleAlert.findMany({ where: { recipientId, state: "active" }, include: { grant: { include: { alertPolicy: true } }, dose: { include: { prescription: { select: { archivedAt: true } } } } }, take: 500 });
    for (const alert of active) {
      const p = alert.grant.alertPolicy;
      const reason = !p?.enabled ? "owner_disabled" : !p.recipientConsented ? "recipient_withdrew_consent" : !alert.grant.shareDoseStatus ? "permission_removed" : !(await this.entitled(alert.ownerId)) ? "entitlement_lost" : alert.dose.status !== "unconfirmed" || alert.dose.takenAt || alert.dose.canceledAt || alert.dose.snoozedUntil || alert.dose.prescription.archivedAt ? "occurrence_resolved" : null;
      if (reason) await this.db.circleAlert.updateMany({ where: { id: alert.id, recipientId, state: "active" }, data: { state: "cancelled", cancelReason: reason } });
    }
  }

  async inbox(recipientId: string, limit = 50) {
    await this.cancelIneligible(recipientId);
    const alerts = await this.db.circleAlert.findMany({ where: { recipientId, state: "active", grant: { recipientId, shareDoseStatus: true, alertPolicy: { enabled: true, recipientConsented: true } }, dose: { status: "unconfirmed", takenAt: null, canceledAt: null, snoozedUntil: null, prescription: { archivedAt: null } }, owner: { billingSubscriptions: { some: activeSubscription(this.now()) } } }, include: { owner: { select: { id: true, name: true } }, grant: { select: { shareReminders: true } } }, orderBy: { createdAt: "desc" }, take: Math.min(Math.max(limit, 1), 100) });
    return { alerts: alerts.map(a => ({ id: a.id, grantId: a.grantId, owner: { id: a.owner.id, displayName: a.owner.name?.trim() || "Circle member" }, doseId: a.doseId, kind: "confirmation_not_recorded", scheduledFor: a.grant.shareReminders ? a.scheduledFor : null, createdAt: a.createdAt, readAt: a.readAt, notice: CIRCLE_ALERT_NOTICE })), notice: CIRCLE_ALERT_NOTICE };
  }

  async markRead(recipientId: string, alertId: string) {
    await this.cancelIneligible(recipientId);
    const now = this.now();
    const result = await this.db.circleAlert.updateMany({ where: { id: alertId, recipientId, state: "active", grant: { recipientId, shareDoseStatus: true, alertPolicy: { enabled: true, recipientConsented: true } }, dose: { status: "unconfirmed", takenAt: null, canceledAt: null, snoozedUntil: null, prescription: { archivedAt: null } }, owner: { billingSubscriptions: { some: activeSubscription(now) } } }, data: { readAt: now } });
    if (result.count !== 1) throw new ConsumerError(404, "Alert not found.");
    return { id: alertId, readAt: now };
  }
}
