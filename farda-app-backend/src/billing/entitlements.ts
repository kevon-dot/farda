import type { PrismaClient } from '../../generated/prisma/client';
import { nativeEntitled, refreshNativeIfNeeded } from './native';

export type PaidCapability = 'ai_refill_help' | 'family_alerts';
const liveStatuses = ['active', 'trialing'] as const;

type EntitlementDb = Pick<PrismaClient, 'billingSubscription'> & Partial<Pick<PrismaClient, 'nativeBillingSubscription'>>;
export async function hasEntitlement(db: EntitlementDb, userId: string, capability: PaidCapability) {
  const tiers = capability === 'family_alerts' ? ['family'] : ['plus', 'family'];
  const web = await db.billingSubscription.findFirst({ where: { userId, tier: { in: tiers }, status: { in: [...liveStatuses] }, currentPeriodEnd: { gt: new Date() } }, select: { id: true } });
  if (web) return true;
  const native = db.nativeBillingSubscription ? await refreshNativeIfNeeded(db, userId) ?? await db.nativeBillingSubscription.findUnique({ where: { userId } }) : null;
  return nativeEntitled(native, capability);
}

// Keep existing users on the guided/AI refill path until the paywall rollout is explicitly enabled.
export async function canUseAiRefill(db: EntitlementDb, userId: string) {
  return process.env.FARDA_AI_REFILL_PAYWALL_ENABLED !== 'true' || hasEntitlement(db, userId, 'ai_refill_help');
}
