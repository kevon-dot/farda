import { z } from 'zod';
import type { PrismaClient } from '../../generated/prisma/client';
import { ConsumerError } from '../reminders/policy';
import type { RefillsProvider } from './providers/types';
import { lock, serial } from '../reminders/service';

const identifier = z.string().trim().min(1).max(160);
export const providerLinkInput = z.object({
  userId: identifier, prescriptionId: identifier, patientId: identifier,
  providerPrescriptionId: identifier, pharmacyId: identifier,
  environment: z.enum(['sandbox', 'production']),
  // A trusted operator must compare the actual records. Name similarity or OCR
  // output is not enough evidence to map a clinical prescription automatically.
  reviewedMedicationMatch: z.literal(true),
}).strict();

export async function provisionRefillLink(db: PrismaClient, provider: RefillsProvider, input: z.infer<typeof providerLinkInput>, apply = false) {
  const checked = providerLinkInput.parse(input);
  if (!provider.configured || provider.environment !== checked.environment) throw new ConsumerError(409, 'Provider environment is not configured.');
  const prescription = await db.prescription.findFirst({ where: { id: checked.prescriptionId, userId: checked.userId, archivedAt: null } });
  if (!prescription) throw new ConsumerError(404, 'Prescription not found.');
  await provider.verifyLink({ userId: checked.userId, patientId: checked.patientId, prescriptionId: checked.providerPrescriptionId, pharmacyId: checked.pharmacyId });
  if (!apply) return { verified: true, applied: false, environment: checked.environment };
  await serial(db, async tx => {
    await lock(tx, `refill-agent:${checked.userId}`);
    const current = await tx.prescription.findFirst({ where: { id: checked.prescriptionId, userId: checked.userId, archivedAt: null } });
    if (!current || current.updatedAt.getTime() !== prescription.updatedAt.getTime()) throw new ConsumerError(409, 'Prescription changed during verification.');
    const active = await tx.refillAgentRequest.findFirst({ where: { userId: checked.userId, prescriptionId: checked.prescriptionId, status: { in: ['submitting', 'unknown', 'sent', 'received', 'ready', 'shipped'] } } });
    if (active) throw new ConsumerError(409, 'Resolve the existing refill request before changing its connection.');
    const duplicate = await tx.refillProviderLink.findFirst({ where: { environment: checked.environment, patientId: checked.patientId, providerPrescriptionId: checked.providerPrescriptionId, prescriptionId: { not: checked.prescriptionId } } });
    if (duplicate) throw new ConsumerError(409, 'This provider prescription is already linked.');
    const data = { userId: checked.userId, patientId: checked.patientId, providerPrescriptionId: checked.providerPrescriptionId, pharmacyId: checked.pharmacyId, environment: checked.environment, enabled: true };
    await tx.refillProviderLink.upsert({ where: { prescriptionId: checked.prescriptionId }, create: { prescriptionId: checked.prescriptionId, ...data }, update: data });
  });
  return { verified: true, applied: true, environment: checked.environment };
}
