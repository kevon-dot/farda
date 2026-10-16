import { describe, expect, it, vi } from 'vitest';
import { provisionRefillLink } from '../src/refills/provision';
import type { RefillsProvider, VerifiedProviderLink } from '../src/refills/providers/types';
import { memoryDb } from './consumer-memory-db';

function fixture() {
  const stamp = new Date('2026-10-16T00:00:00Z');
  const memory = memoryDb({ prescription: [{ id: 'rx', userId: 'owner', archivedAt: null, updatedAt: stamp }] });
  const input = { userId: 'owner', prescriptionId: 'rx', patientId: 'patient', providerPrescriptionId: 'remote-rx', pharmacyId: 'pharmacy', environment: 'sandbox' as const, reviewedMedicationMatch: true as const };
  const verified: VerifiedProviderLink = { patientId: 'patient', prescriptionId: 'remote-rx', pharmacyId: 'pharmacy', pharmacyName: 'Synthetic pharmacy', medicationName: 'Synthetic medication', instructions: 'Synthetic label', fillsRemaining: 1, expirationDate: '2027-01-01', effectiveDate: '2026-01-01', prescriptionState: 'ACTIVE', address: { street1: 'Synthetic street', postalCode: '11111', country: 'USA', state: 'NY', city: 'Synthetic city' } };
  const provider = { configured: true as boolean, environment: 'sandbox' as const, verifyLink: vi.fn(async () => verified), submitOrder: vi.fn(), getOrder: vi.fn(), findOrder: vi.fn() } satisfies RefillsProvider;
  return { ...memory, input, provider };
}

describe('trusted refill mapping provisioning', () => {
  it('defaults to verification only, leaving all persisted state untouched', async () => {
    const f = fixture();
    expect(await provisionRefillLink(f.db, f.provider, f.input)).toEqual({ verified: true, applied: false, environment: 'sandbox' });
    expect(f.provider.verifyLink).toHaveBeenCalledWith({ userId: 'owner', patientId: 'patient', prescriptionId: 'remote-rx', pharmacyId: 'pharmacy' });
    expect(f.rows('refillProviderLink')).toHaveLength(0);
    expect(f.rows('refillAgentRequest')).toHaveLength(0);
    expect(f.provider.submitOrder).not.toHaveBeenCalled();
  });
  it('requires explicit human medication matching and configured environment', async () => {
    const f = fixture();
    await expect(provisionRefillLink(f.db, f.provider, { ...f.input, reviewedMedicationMatch: false as never }, true)).rejects.toThrow();
    await expect(provisionRefillLink(f.db, f.provider, { ...f.input, environment: 'production' }, true)).rejects.toMatchObject({ status: 409 });
    f.provider.configured = false;
    await expect(provisionRefillLink(f.db, f.provider, f.input, true)).rejects.toMatchObject({ status: 409 });
    expect(f.provider.verifyLink).not.toHaveBeenCalled();
    expect(f.provider.submitOrder).not.toHaveBeenCalled();
  });
  it('checks ownership before contacting a provider and rejects archived records', async () => {
    const f = fixture();
    await expect(provisionRefillLink(f.db, f.provider, { ...f.input, userId: 'other' }, true)).rejects.toMatchObject({ status: 404 });
    await f.db.prescription.update({ where: { id: 'rx' }, data: { archivedAt: new Date() } });
    await expect(provisionRefillLink(f.db, f.provider, f.input, true)).rejects.toMatchObject({ status: 404 });
    expect(f.provider.verifyLink).not.toHaveBeenCalled();
  });
  it('applies only an explicitly verified link and never creates an order', async () => {
    const f = fixture();
    expect(await provisionRefillLink(f.db, f.provider, f.input, true)).toEqual({ verified: true, applied: true, environment: 'sandbox' });
    expect(f.rows('refillProviderLink')).toMatchObject([{ userId: 'owner', prescriptionId: 'rx', environment: 'sandbox', patientId: 'patient', providerPrescriptionId: 'remote-rx', enabled: true }]);
    expect(f.provider.submitOrder).not.toHaveBeenCalled();
    expect(f.provider.getOrder).not.toHaveBeenCalled();
    expect(f.provider.findOrder).not.toHaveBeenCalled();
  });
  it('rolls back if the local prescription changes while provider verification is in flight', async () => {
    const f = fixture();
    f.raw.beforeTransaction = async () => { await f.db.prescription.update({ where: { id: 'rx' }, data: { medicationName: 'Edited record' } }); };
    await expect(provisionRefillLink(f.db, f.provider, f.input, true)).rejects.toMatchObject({ status: 409 });
    expect(f.rows('refillProviderLink')).toHaveLength(0);
  });
  it.each(['submitting', 'unknown', 'sent', 'received', 'ready', 'shipped'])('does not relink an unresolved %s request', async status => {
    const f = fixture();
    await f.db.refillAgentRequest.create({ data: { userId: 'owner', prescriptionId: 'rx', status } as never });
    await expect(provisionRefillLink(f.db, f.provider, f.input, true)).rejects.toMatchObject({ status: 409 });
    expect(f.rows('refillProviderLink')).toHaveLength(0);
    expect(f.provider.submitOrder).not.toHaveBeenCalled();
  });
  it.each([true, false])('rejects an external prescription already mapped elsewhere (enabled=%s)', async enabled => {
    const f = fixture();
    await f.db.refillProviderLink.create({ data: { userId: 'owner', prescriptionId: 'other-local-rx', patientId: 'patient', providerPrescriptionId: 'remote-rx', pharmacyId: 'pharmacy', environment: 'sandbox', enabled } });
    await expect(provisionRefillLink(f.db, f.provider, f.input, true)).rejects.toMatchObject({ status: 409 });
    expect(f.rows('refillProviderLink')).toHaveLength(1);
  });
  it('does not write a mapping if verification fails', async () => {
    const f = fixture();
    f.provider.verifyLink.mockRejectedValueOnce(new Error('Synthetic private provider response'));
    await expect(provisionRefillLink(f.db, f.provider, f.input, true)).rejects.toThrow();
    expect(f.rows('refillProviderLink')).toHaveLength(0);
    expect(f.provider.submitOrder).not.toHaveBeenCalled();
  });
});
