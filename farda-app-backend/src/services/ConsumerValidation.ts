import { Temporal } from '@js-temporal/polyfill';
import { z } from 'zod';

export class ConsumerError extends Error {
  constructor(public status: number, public code: string, message: string) { super(message); }
}

const optionalText = (max: number) => z.string().trim().max(max).nullish();
export const isoInstant = z.string().datetime({ offset: true });
export const dateOnly = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => {
  try { return Temporal.PlainDate.from(value).toString() === value; } catch { return false; }
}, 'Use a valid YYYY-MM-DD date');
export const timeZone = z.string().max(100).refine(value => {
  try { new Intl.DateTimeFormat('en', { timeZone: value }); return !/^[+-]/.test(value); } catch { return false; }
}, 'Use an IANA timezone');

export const ScheduleInput = z.object({
  recurrence: z.literal('daily'),
  times: z.array(z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/)).min(1).max(4)
    .refine(times => new Set(times).size === times.length, 'Reminder times must be unique'),
  timezone: timeZone,
  startDate: dateOnly,
  durationDays: z.number().int().min(1).max(366),
  effectiveAt: isoInstant.optional(),
}).strict();
export type ScheduleDraft = z.infer<typeof ScheduleInput>;

export const PrescriptionInput = z.object({
  clientRequestId: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._:-]{7,99}$/, 'Use a stable request ID of 8–100 characters'),
  medicationName: z.string().trim().min(1).max(200),
  dosageInstructions: optionalText(2000),
  labelReviewed: z.literal(true),
  rxNumber: optionalText(100), storeNumber: optionalText(100),
  pharmacyOrDoctorName: optionalText(200), contactDetails: optionalText(300),
  address: optionalText(500), dateFilled: dateOnly.nullish(), dateExpired: dateOnly.nullish(),
  deviceId: optionalText(200), schedule: ScheduleInput.optional(),
}).strict().superRefine((value, ctx) => {
  if (value.schedule && !value.dosageInstructions?.trim()) {
    ctx.addIssue({ code: 'custom', path: ['dosageInstructions'], message: 'Review the label directions before activating reminders' });
  }
});

export const PrescriptionPatch = z.object({
  medicationName: z.string().trim().min(1).max(200).optional(),
  dosageInstructions: optionalText(2000), labelReviewed: z.literal(true),
  rxNumber: optionalText(100), storeNumber: optionalText(100),
  pharmacyOrDoctorName: optionalText(200), contactDetails: optionalText(300), address: optionalText(500),
  dateFilled: dateOnly.nullish(), dateExpired: dateOnly.nullish(),
}).strict();

export const DosePatch = z.object({
  status: z.enum(['unconfirmed', 'taken', 'skipped']).optional(),
  takenAt: isoInstant.nullish(), mood: optionalText(100), note: optionalText(2000),
  reason: optionalText(500), expectedRevision: z.number().int().min(0).optional(),
}).strict().superRefine((value, ctx) => {
  if (value.takenAt !== undefined && value.status !== 'taken') ctx.addIssue({ code: 'custom', path: ['status'], message: 'takenAt requires an explicit taken status' });
  if (value.status === 'taken' && value.takenAt === null) ctx.addIssue({ code: 'custom', path: ['takenAt'], message: 'A taken record needs a time' });
  if (value.status === undefined && value.note === undefined && value.mood === undefined) ctx.addIssue({ code: 'custom', message: 'Supply status, note or mood' });
});

/** Each daily wall-clock time is resolved independently, never by adding 24h.
 * DST gaps/folds are rejected instead of silently moving or doubling a reminder.
 */
export function generateOccurrences(input: ScheduleDraft, effectiveAt: Date): Date[] {
  const start = Temporal.PlainDate.from(input.startDate);
  const dates: Date[] = [];
  for (let day = 0; day < input.durationDays; day++) {
    const date = start.add({ days: day });
    for (const time of input.times) {
      try {
        const local = date.toPlainDateTime(Temporal.PlainTime.from(time));
        const instant = local.toZonedDateTime(input.timezone, { disambiguation: 'reject' }).toInstant();
        const scheduled = new Date(Number(instant.epochMilliseconds));
        if (scheduled >= effectiveAt) dates.push(scheduled);
      } catch {
        throw new ConsumerError(422, 'ambiguous_local_time', `The reminder time ${time} on ${date} is ambiguous or unavailable in ${input.timezone}. Choose another time.`);
      }
    }
  }
  if (!dates.length) throw new ConsumerError(422, 'no_future_occurrences', 'This schedule has no upcoming reminder times');
  return dates.sort((a, b) => a.getTime() - b.getTime());
}

export function doseChanges(input: z.infer<typeof DosePatch>, now: Date) {
  const changes: { status?: string; source?: string; takenAt?: Date | null; note?: string | null; mood?: string | null } = {};
  if (input.note !== undefined) changes.note = input.note;
  if (input.mood !== undefined) changes.mood = input.mood;
  if (input.status !== undefined) {
    changes.status = input.status;
    changes.source = 'self_report';
    changes.takenAt = input.status === 'taken' ? (input.takenAt ? new Date(input.takenAt) : now) : null;
    if (changes.takenAt && changes.takenAt > now) throw new ConsumerError(422, 'future_taken_time', 'A taken time cannot be in the future');
  }
  return changes;
}
