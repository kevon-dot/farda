import type { PrismaClient } from '../../generated/prisma/client';

export type PaidCapability = 'ai_refill_help' | 'family_alerts';
const liveStatuses = ['active', 'trialing'] as const;

export async function hasEntitlement(db: Pick<PrismaClient, 'billingSubscription'>, userId: string, capability: PaidCapability) {
  const tiers = capability === 'family_alerts' ? ['family'] : ['plus', 'family'];
  return Boolean(await db.billingSubscription.findFirst({ where: { userId, tier: { in: tiers }, status: { in: [...liveStatuses] }, currentPeriodEnd: { gt: new Date() } }, select: { id: true } }));
}

// Keep existing users on the guided/AI refill path until the paywall rollout is explicitly enabled.
export async function canUseAiRefill(db: Pick<PrismaClient, 'billingSubscription'>, userId: string) {
  return process.env.FARDA_AI_REFILL_PAYWALL_ENABLED !== 'true' || hasEntitlement(db, userId, 'ai_refill_help');
}
