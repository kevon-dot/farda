import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../generated/prisma/client';
import { RefillAgentService } from '../src/refills/agent';
import { RefillProviderError, type ProviderOrder, type RefillsProvider } from '../src/refills/providers/types';

// Explicit disposable database only: never fall back to DATABASE_URL, migrate,
// truncate, or delete unrelated records. The runner applies migrations first.
const databaseUrl = process.env.TEST_DATABASE_URL;
const singleConnection = process.env.TEST_DATABASE_SINGLE_CONNECTION === 'true';
describe.skipIf(!databaseUrl)('refill agent PostgreSQL reservation and constraints', () => {
  let db: PrismaClient;
  const prefix = `refill-agent-it-${randomUUID()}`;
  const userId = `${prefix}-owner`, otherId = `${prefix}-other`;
  beforeAll(async () => {
    db = new PrismaClient({ adapter: new PrismaPg({ connectionString: databaseUrl!, max: singleConnection ? 1 : 6 }) });
    await db.user.createMany({ data: [{ id: userId }, { id: otherId }] });
  }, 30_000);
  afterAll(async () => {
    if (!db) return;
    // Request -> review is RESTRICT, so delete requests explicitly before the
    // account cascade. Restrict cleanup to this run's synthetic account IDs.
    await db.refillAgentRequest.deleteMany({ where: { userId: { in: [userId, otherId] } } });
    await db.user.deleteMany({ where: { id: { in: [userId, otherId] } } });
    await db.$disconnect();
  });

  async function fixture() {
    const prescriptionId = `${prefix}-${randomUUID()}`;
    const patientId = `${prefix}-patient`, remoteId = `${prescriptionId}-remote`;
    await db.prescription.create({ data: { id: prescriptionId, userId, medicationName: 'Synthetic integration medication' } });
    const link = await db.refillProviderLink.create({ data: { userId, prescriptionId, environment: 'sandbox', patientId, providerPrescriptionId: remoteId, pharmacyId: 'synthetic-pharmacy', enabled: true } });
    const order = (externalId: string): ProviderOrder => ({ id: `order-${externalId}`, externalId, patientId, prescriptionIds: [remoteId], pharmacyId: 'synthetic-pharmacy', orderState: 'PENDING', fulfillmentType: null, fulfillmentState: null });
    const provider = {
      configured: true, environment: 'sandbox' as const,
      verifyLink: vi.fn(async () => ({ patientId, prescriptionId: remoteId, pharmacyId: 'synthetic-pharmacy', pharmacyName: 'Synthetic pharmacy', medicationName: 'Synthetic medication', instructions: 'Synthetic label', fillsRemaining: 1, expirationDate: '2027-01-01', effectiveDate: '2026-01-01', prescriptionState: 'ACTIVE', address: { street1: 'Synthetic street', postalCode: '11111', country: 'USA', state: 'NY', city: 'Synthetic city' } })),
      submitOrder: vi.fn(async ({ externalId }: { externalId: string }) => order(externalId)),
      getOrder: vi.fn(async () => null as ProviderOrder | null), findOrder: vi.fn(async () => null as ProviderOrder | null),
    } satisfies RefillsProvider;
    const service = new RefillAgentService(db, provider);
    const review = await service.review(userId, prescriptionId);
    const input = { reviewToken: (review.review as { token: string }).token, confirmed: true, idempotencyKey: randomUUID() };
    return { prescriptionId, link, provider, service, input, order };
  }

  it.skipIf(singleConnection)('reserves one durable attempt across simultaneous identical submissions', async () => {
    const f = await fixture();
    const results = await Promise.all([f.service.submit(userId, f.prescriptionId, f.input), f.service.submit(userId, f.prescriptionId, f.input)]);
    expect(results[0].latestRequest?.id).toBe(results[1].latestRequest?.id);
    expect(f.provider.submitOrder).toHaveBeenCalledTimes(1);
    expect(await db.refillAgentRequest.count({ where: { userId, prescriptionId: f.prescriptionId } })).toBe(1);
    expect(await db.inventoryEntry.count({ where: { prescriptionId: f.prescriptionId } })).toBe(0);
  });
  it.skipIf(singleConnection)('blocks a competing key at the same review before a second provider send', async () => {
    const f = await fixture();
    const results = await Promise.allSettled([f.service.submit(userId, f.prescriptionId, f.input), f.service.submit(userId, f.prescriptionId, { ...f.input, idempotencyKey: randomUUID() })]);
    expect(results.filter(r => r.status === 'fulfilled')).toHaveLength(1);
    expect(results.find(r => r.status === 'rejected')).toMatchObject({ reason: { status: 409 } });
    expect(f.provider.submitOrder).toHaveBeenCalledTimes(1);
    expect(await db.refillAgentRequest.count({ where: { userId, prescriptionId: f.prescriptionId } })).toBe(1);
  });
  it('preserves an uncertain outcome across service restart and blocks all resubmissions', async () => {
    const f = await fixture();
    f.provider.submitOrder.mockRejectedValueOnce(new RefillProviderError('provider_timeout', 'unknown'));
    expect((await f.service.submit(userId, f.prescriptionId, f.input)).latestRequest?.status).toBe('unknown');
    const restarted = new RefillAgentService(db, f.provider);
    expect((await restarted.review(userId, f.prescriptionId)).canSubmit).toBe(false);
    expect((await restarted.refresh(userId, f.prescriptionId)).latestRequest?.status).toBe('unknown');
    await restarted.submit(userId, f.prescriptionId, f.input);
    await expect(restarted.submit(userId, f.prescriptionId, { ...f.input, idempotencyKey: randomUUID() })).rejects.toMatchObject({ status: 409 });
    expect(f.provider.submitOrder).toHaveBeenCalledTimes(1);
  });
  it('enforces external prescription mapping uniqueness in the database, even for a disabled link', async () => {
    const f = await fixture();
    const duplicateId = `${prefix}-${randomUUID()}`;
    await db.prescription.create({ data: { id: duplicateId, userId, medicationName: 'Synthetic duplicate local record' } });
    await expect(db.refillProviderLink.create({ data: { userId, prescriptionId: duplicateId, environment: 'sandbox', patientId: f.link.patientId, providerPrescriptionId: f.link.providerPrescriptionId, pharmacyId: f.link.pharmacyId, enabled: false } })).rejects.toMatchObject({ code: 'P2002' });
    expect(await db.refillProviderLink.count({ where: { prescriptionId: duplicateId } })).toBe(0);
  });
  it('rejects stale local and connection revisions without reserving or sending', async () => {
    const f = await fixture();
    await db.prescription.update({ where: { id: f.prescriptionId }, data: { medicationName: 'Synthetic changed medication', updatedAt: new Date(Date.now() + 1000) } });
    await expect(f.service.submit(userId, f.prescriptionId, f.input)).rejects.toMatchObject({ status: 409 });
    const newReview = await f.service.review(userId, f.prescriptionId);
    await db.refillProviderLink.update({ where: { id: f.link.id }, data: { updatedAt: new Date(Date.now() + 2000) } });
    await expect(f.service.submit(userId, f.prescriptionId, { ...f.input, reviewToken: (newReview.review as { token: string }).token })).rejects.toMatchObject({ status: 409 });
    expect(f.provider.submitOrder).not.toHaveBeenCalled();
    expect(await db.refillAgentRequest.count({ where: { prescriptionId: f.prescriptionId } })).toBe(0);
  });
  it('checks ownership before provider calls for every entry point', async () => {
    const f = await fixture();
    f.provider.verifyLink.mockClear();
    await expect(f.service.review(otherId, f.prescriptionId)).rejects.toMatchObject({ status: 404 });
    await expect(f.service.submit(otherId, f.prescriptionId, f.input)).rejects.toMatchObject({ status: 404 });
    await expect(f.service.refresh(otherId, f.prescriptionId)).rejects.toMatchObject({ status: 404 });
    expect(f.provider.verifyLink).not.toHaveBeenCalled();
    expect(f.provider.submitOrder).not.toHaveBeenCalled();
    expect(f.provider.findOrder).not.toHaveBeenCalled();
  });
  it.skipIf(singleConnection)('coalesces simultaneous refreshes before calling the provider', async () => {
    const f = await fixture();
    const submitted = await f.service.submit(userId, f.prescriptionId, f.input);
    f.provider.getOrder.mockResolvedValue(f.order(submitted.latestRequest!.id));
    await Promise.all([f.service.refresh(userId, f.prescriptionId), f.service.refresh(userId, f.prescriptionId)]);
    expect(f.provider.getOrder).toHaveBeenCalledTimes(1);
    expect(f.provider.submitOrder).toHaveBeenCalledTimes(1);
  });
});
