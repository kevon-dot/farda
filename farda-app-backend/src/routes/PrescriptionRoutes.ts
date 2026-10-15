import { prisma } from '@src/lib/prisma';
import { createHash } from 'node:crypto';
import { ConsumerError, DosePatch, PrescriptionInput, PrescriptionPatch, ScheduleInput, doseChanges, generateOccurrences, isoInstant, type ScheduleDraft } from '@src/services/ConsumerValidation';
import type { Prisma } from '../../generated/prisma/client';
import type { Request, Response } from 'express';
import { z } from 'zod';
import { cancelOccurrenceReminders, serial } from '../reminders/service';

export function authenticatedUser(req: Request) {
  if (!req.user?.id) throw new ConsumerError(401, 'unauthorized', 'Sign in to continue');
  return req.user.id;
}
export function sendConsumerError(res: Response, error: unknown) {
  if (error instanceof ConsumerError) return res.status(error.status).json({ error: error.message, code: error.code });
  if (error instanceof z.ZodError) return res.status(400).json({ error: 'Check the supplied fields', code: 'invalid_input', details: error.issues.map(i => ({ path: i.path, message: i.message })) });
  if (typeof error === 'object' && error && 'code' in error && ['P2002', 'P2034'].includes(String(error.code))) return res.status(409).json({ error: 'This record changed. Reload and try again.', code: 'conflict' });
  return res.status(503).json({ error: 'We could not save or load your records. Please try again.', code: 'temporarily_unavailable' });
}
const asJson = (value: unknown) => JSON.parse(JSON.stringify(value)) as Prisma.InputJsonValue;
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort().filter(key => (value as Record<string, unknown>)[key] !== undefined).map(key => `${JSON.stringify(key)}:${canonical((value as Record<string, unknown>)[key])}`).join(',')}}`;
  return JSON.stringify(value) ?? 'null';
}
function publicPrescription<T extends { requestHash?: string | null; clientRequestId?: string | null }>(record: T) {
  const { requestHash, clientRequestId, ...data } = record;
  return data;
}
function matchingRequest<T extends { requestHash: string | null }>(record: T, hash: string): T {
  if (record.requestHash !== hash) throw new ConsumerError(409, 'idempotency_conflict', 'This save ID was already used for a different draft. Review it before saving again.');
  return record;
}
const recordFields = (input: z.infer<typeof PrescriptionPatch> | z.infer<typeof PrescriptionInput>) => {
  const { labelReviewed, dateFilled, dateExpired, ...rest } = input;
  const data: Record<string, unknown> = { ...rest, labelReviewedAt: new Date() };
  delete data.schedule; delete data.deviceId;
  if (dateFilled !== undefined) data.dateFilled = dateFilled ? new Date(`${dateFilled}T00:00:00Z`) : null;
  if (dateExpired !== undefined) data.dateExpired = dateExpired ? new Date(`${dateExpired}T00:00:00Z`) : null;
  return data;
};

async function addSchedule(tx: Prisma.TransactionClient, userId: string, prescriptionId: string, input: ScheduleDraft, now: Date) {
  const effectiveAt = input.effectiveAt ? new Date(input.effectiveAt) : now;
  if (effectiveAt < now) throw new ConsumerError(422, 'past_effective_time', 'Schedule changes must take effect now or in the future');
  const occurrences = generateOccurrences(input, effectiveAt);
  const latest = await tx.scheduleVersion.findFirst({ where: { prescriptionId }, orderBy: { version: 'desc' } });
  await tx.scheduleVersion.updateMany({ where: { prescriptionId, endedAt: null, effectiveAt: { lte: effectiveAt } }, data: { endedAt: effectiveAt } });
  const futureVersions = await tx.scheduleVersion.findMany({ where: { prescriptionId, endedAt: null, effectiveAt: { gt: effectiveAt } }, select: { id: true, effectiveAt: true } });
  for (const future of futureVersions) await tx.scheduleVersion.update({ where: { id: future.id }, data: { endedAt: future.effectiveAt } });
  // Preserve every row. Only replace future unconfirmed reminders.
  const replaced = await tx.dose.findMany({ where: { userId, prescriptionId, status: 'unconfirmed', scheduledFor: { gte: effectiveAt } }, select: { id: true } });
  await tx.dose.updateMany({ where: { id: { in: replaced.map(dose => dose.id) }, userId }, data: { status: 'cancelled', canceledAt: now, revision: { increment: 1 } } });
  await cancelOccurrenceReminders(tx, replaced.map(dose => dose.id), 'schedule_changed');
  const schedule = await tx.scheduleVersion.create({ data: {
    prescriptionId, version: (latest?.version ?? 0) + 1, timezone: input.timezone,
    recurrence: input.recurrence, times: input.times, startDate: new Date(`${input.startDate}T00:00:00Z`), durationDays: input.durationDays, effectiveAt,
  } });
  const alreadyRecorded = await tx.dose.findMany({ where: { prescriptionId, userId, status: { in: ['taken', 'skipped'] }, scheduledFor: { in: occurrences } }, select: { scheduledFor: true } });
  const terminalTimes = new Set(alreadyRecorded.map(dose => dose.scheduledFor.getTime()));
  const newOccurrences = occurrences.filter(time => !terminalTimes.has(time.getTime()));
  if (newOccurrences.length) await tx.dose.createMany({ data: newOccurrences.map(scheduledFor => ({ userId, prescriptionId, scheduledFor, scheduleVersionId: schedule.id, status: 'unconfirmed', source: 'schedule' })) });
  return schedule;
}

export const createPrescription = async (req: Request, res: Response) => {
  let owner: string | undefined, clientRequestId: string | undefined, requestHash: string | undefined;
  try {
    const userId = authenticatedUser(req);
    const input = PrescriptionInput.parse(req.body);
    owner = userId; clientRequestId = input.clientRequestId;
    requestHash = createHash('sha256').update(canonical(input)).digest('hex');
    const hash = requestHash;
    if (input.deviceId) throw new ConsumerError(409, 'pairing_required', 'Save your prescription first, then pair your vial through verified setup');
    const now = new Date();
    const result = await serial(prisma, async tx => {
      const existing = await tx.prescription.findUnique({ where: { userId_clientRequestId: { userId, clientRequestId: input.clientRequestId } }, include: { schedules: { orderBy: { version: 'desc' } } } });
      if (existing) return { record: matchingRequest(existing, hash), created: false };
      const record = await tx.prescription.create({ data: { ...recordFields(input), medicationName: input.medicationName, userId, clientRequestId: input.clientRequestId, requestHash: hash } });
      if (input.schedule) await addSchedule(tx, userId, record.id, input.schedule, now);
      return { record: await tx.prescription.findUniqueOrThrow({ where: { id: record.id }, include: { schedules: { orderBy: { version: 'desc' } } } }), created: true };
    });
    return res.status(result.created ? 201 : 200).json({ data: publicPrescription(result.record) });
  } catch (error) {
    // A racing identical request may commit while this serializable transaction
    // loses its unique-index/serialization race. Return that committed record;
    // never run schedule generation again on an uncertain retry.
    if (owner && clientRequestId && requestHash && typeof error === 'object' && error && 'code' in error && ['P2002', 'P2034'].includes(String(error.code))) {
      try {
        const existing = await prisma.prescription.findUnique({ where: { userId_clientRequestId: { userId: owner, clientRequestId } }, include: { schedules: { orderBy: { version: 'desc' } } } });
        if (existing) return res.json({ data: publicPrescription(matchingRequest(existing, requestHash)) });
      } catch (lookupError) { return sendConsumerError(res, lookupError); }
    }
    return sendConsumerError(res, error);
  }
};

export const listPrescriptions = async (req: Request, res: Response) => {
  try {
    const userId = authenticatedUser(req);
    if (req.params.userId && req.params.userId !== userId) throw new ConsumerError(404, 'not_found', 'Record not found');
    const data = await prisma.prescription.findMany({ where: { userId, archivedAt: null }, include: { schedules: { orderBy: { version: 'desc' } } }, orderBy: { createdAt: 'asc' } });
    return res.json({ data: data.map(publicPrescription) });
  } catch (error) { return sendConsumerError(res, error); }
};

export const updatePrescription = async (req: Request, res: Response) => {
  try {
    const userId = authenticatedUser(req);
    const input = PrescriptionPatch.parse(req.body);
    const data = await serial(prisma, async tx => {
      const owned = await tx.prescription.findFirst({ where: { id: String(req.params.id), userId, archivedAt: null } });
      if (!owned) throw new ConsumerError(404, 'not_found', 'Record not found');
      if (input.dosageInstructions === null || input.dosageInstructions === '') throw new ConsumerError(422, 'directions_required', 'Keep the reviewed directions; edit reminders separately');
      return tx.prescription.update({ where: { id: owned.id }, data: recordFields(input) });
    });
    return res.json({ data: publicPrescription(data) });
  } catch (error) { return sendConsumerError(res, error); }
};

export const changeSchedule = async (req: Request, res: Response) => {
  try {
    const userId = authenticatedUser(req);
    const input = ScheduleInput.parse(req.body);
    const data = await serial(prisma, async tx => {
      const owned = await tx.prescription.findFirst({ where: { id: String(req.params.id), userId, archivedAt: null } });
      if (!owned) throw new ConsumerError(404, 'not_found', 'Record not found');
      if (!owned.labelReviewedAt || !owned.dosageInstructions) throw new ConsumerError(422, 'label_review_required', 'Review your prescription label before activating reminders');
      return addSchedule(tx, userId, owned.id, input, new Date());
    });
    return res.status(201).json({ data });
  } catch (error) { return sendConsumerError(res, error); }
};

export const archivePrescription = async (req: Request, res: Response) => {
  try {
    const userId = authenticatedUser(req);
    const now = new Date();
    await serial(prisma, async tx => {
      const owned = await tx.prescription.findFirst({ where: { id: String(req.params.id), userId } });
      if (!owned) throw new ConsumerError(404, 'not_found', 'Record not found');
      await tx.prescription.update({ where: { id: owned.id }, data: { archivedAt: now } });
      await tx.scheduleVersion.updateMany({ where: { prescriptionId: owned.id, endedAt: null }, data: { endedAt: now } });
      const cancelled = await tx.dose.findMany({ where: { userId, prescriptionId: owned.id, status: 'unconfirmed', scheduledFor: { gte: now } }, select: { id: true } });
      await tx.dose.updateMany({ where: { id: { in: cancelled.map(dose => dose.id) }, userId }, data: { status: 'cancelled', canceledAt: now, revision: { increment: 1 } } });
      await cancelOccurrenceReminders(tx, cancelled.map(dose => dose.id), 'prescription_archived');
    });
    return res.status(204).end();
  } catch (error) { return sendConsumerError(res, error); }
};

export const listDoses = async (req: Request, res: Response) => {
  try {
    const userId = authenticatedUser(req);
    if (req.params.userId && req.params.userId !== userId) throw new ConsumerError(404, 'not_found', 'Record not found');
    const query = z.object({ from: isoInstant.optional(), to: isoInstant.optional() }).strict().parse(req.query);
    const from = query.from ? new Date(query.from) : new Date(Date.now() - 31 * 86400000);
    const to = query.to ? new Date(query.to) : new Date(Date.now() + 62 * 86400000);
    if (to <= from || to.getTime() - from.getTime() > 367 * 86400000) throw new ConsumerError(400, 'invalid_range', 'Select a date range of up to one year');
    const data = await prisma.dose.findMany({ where: { userId, scheduledFor: { gte: from, lt: to } }, include: { prescription: { select: { medicationName: true, dosageInstructions: true, archivedAt: true } } }, orderBy: { scheduledFor: 'asc' } });
    return res.json({ data });
  } catch (error) { return sendConsumerError(res, error); }
};

export const recordDose = async (req: Request, res: Response) => {
  try {
    const userId = authenticatedUser(req);
    const input = DosePatch.parse(req.body);
    const changes = doseChanges(input, new Date());
    const doseId = String(req.params.id ?? req.params.doseId);
    const data = await serial(prisma, async tx => {
      const before = await tx.dose.findFirst({ where: { id: doseId, userId } });
      if (!before) throw new ConsumerError(404, 'not_found', 'Record not found');
      if (input.expectedRevision !== undefined && input.expectedRevision !== before.revision) throw new ConsumerError(409, 'conflict', 'This record changed. Reload it before editing');
      if (before.status === 'cancelled' && input.status !== undefined) throw new ConsumerError(409, 'cancelled_occurrence', 'This reminder was cancelled. Choose the active occurrence');
      const changed = await tx.dose.updateMany({ where: { id: doseId, userId, revision: before.revision }, data: { ...changes, revision: { increment: 1 } } });
      if (changed.count !== 1) throw new ConsumerError(409, 'conflict', 'This record changed. Reload it before editing');
      if (input.status === 'taken' || input.status === 'skipped') await cancelOccurrenceReminders(tx, doseId, 'user_resolved');
      const after = await tx.dose.findFirstOrThrow({ where: { id: doseId, userId } });
      await tx.doseCorrection.create({ data: { doseId, actorId: userId, revision: after.revision, before: asJson(before), after: asJson(after), reason: input.reason } });
      return after;
    });
    return res.json({ data });
  } catch (error) { return sendConsumerError(res, error); }
};

export const doseHistory = async (req: Request, res: Response) => {
  try {
    const userId = authenticatedUser(req);
    const doseId = String(req.params.id);
    const owned = await prisma.dose.findFirst({ where: { id: doseId, userId }, select: { id: true } });
    if (!owned) throw new ConsumerError(404, 'not_found', 'Record not found');
    return res.json({ data: await prisma.doseCorrection.findMany({ where: { doseId }, orderBy: { revision: 'asc' } }) });
  } catch (error) { return sendConsumerError(res, error); }
};
