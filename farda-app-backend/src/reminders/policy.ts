export const VOICE_CONSENT_VERSION = "voice-v1";
export const VOICE_CONSENT_TEXT =
	"I agree to automated Farda reminder calls to my verified number. I can turn calls off at any time or press 9 during a call. Calls do not confirm that I took a dose.";
export const CADENCE = Object.freeze({
	beforeMinutes: 10,
	callAfterMinutes: 10,
	windowMinutes: 60,
});

export class ConsumerError extends Error {
	constructor(
		public status: number,
		message: string,
	) {
		super(message);
	}
}
export interface Occurrence {
	id: string;
	userId: string;
	scheduledFor: Date;
	takenAt: Date | null;
	status?: string;
	snoozedUntil: Date | null;
	canceledAt: Date | null;
	revision?: number;
	updatedAt: Date;
}
export interface Preference {
	callsEnabled: boolean;
	liveActivitiesEnabled: boolean;
	timeZone: string;
	quietHoursStart: string;
	quietHoursEnd: string;
	maxCallsPerDay: number;
}
export const DEFAULT_PREFERENCE: Preference = {
	callsEnabled: false,
	liveActivitiesEnabled: false,
	timeZone: "UTC",
	quietHoursStart: "21:00",
	quietHoursEnd: "08:00",
	maxCallsPerDay: 2,
};
export function validTimeZone(value: string) {
	try {
		new Intl.DateTimeFormat("en-US", { timeZone: value }).format();
		return true;
	} catch {
		return false;
	}
}
export function localDay(date: Date, timeZone: string): string {
	const parts = new Intl.DateTimeFormat("en-CA", {
		timeZone,
		year: "numeric",
		month: "2-digit",
		day: "2-digit",
	}).formatToParts(date);
	return ["year", "month", "day"]
		.map((k) => parts.find((p) => p.type === k)!.value)
		.join("-");
}
export function inQuietHours(date: Date, preference: Preference): boolean {
	const parts = new Intl.DateTimeFormat("en-GB", {
		timeZone: preference.timeZone,
		hourCycle: "h23",
		hour: "2-digit",
		minute: "2-digit",
	}).formatToParts(date);
	const minute =
		Number(parts.find((p) => p.type === "hour")!.value) * 60 +
		Number(parts.find((p) => p.type === "minute")!.value);
	const toMinute = (s: string) =>
		Number(s.slice(0, 2)) * 60 + Number(s.slice(3));
	const start = toMinute(preference.quietHoursStart),
		end = toMinute(preference.quietHoursEnd);
	// Equal start/end means quiet all day, not an accidental opt-out of protection.
	return (
		start === end ||
		(start < end
			? minute >= start && minute < end
			: minute >= start || minute < end)
	);
}
export function occurrenceBlock(
	dose: Occurrence | null,
	now: Date,
): string | null {
	if (!dose) return "occurrence_missing";
	if (
		dose.takenAt ||
		dose.canceledAt ||
		(dose.status && dose.status !== "unconfirmed")
	)
		return "occurrence_resolved";
	// An explicit snooze suppresses this occurrence's one phone attempt, even after
	// the snooze ends. Native notifications may resume; an unexpected late call may not.
	if (dose.snoozedUntil) return "occurrence_snoozed";
	if (
		now.getTime() >=
		dose.scheduledFor.getTime() + CADENCE.windowMinutes * 60_000
	)
		return "window_expired";
	return null;
}
export function reminderPlan(dose: Occurrence) {
	const end = new Date(
		dose.scheduledFor.getTime() + CADENCE.windowMinutes * 60_000,
	);
	return [
		{
			channel: "live_activity",
			stage: "before",
			dueAt: new Date(dose.scheduledFor.getTime() - 10 * 60_000),
			// Never turn a delayed heads-up into a surprise start after the due time.
			expiresAt: dose.scheduledFor,
		},
		{
			channel: "live_activity",
			stage: "due",
			dueAt: dose.scheduledFor,
			expiresAt: end,
		},
		{
			channel: "voice",
			stage: "follow_up",
			dueAt: new Date(dose.scheduledFor.getTime() + 10 * 60_000),
			expiresAt: end,
		},
	];
}

const TERMINAL = new Set([
	"completed",
	"busy",
	"failed",
	"no-answer",
	"canceled",
]);
export function acceptProviderEvent(
	currentStatus: string | null,
	currentSequence: number,
	nextStatus: string,
	nextSequence: number,
) {
	const allowed = new Set([
		"queued",
		"initiated",
		"ringing",
		"in-progress",
		...TERMINAL,
	]);
	return (
		allowed.has(nextStatus) &&
		Number.isInteger(nextSequence) &&
		nextSequence >= 0 &&
		nextSequence > currentSequence &&
		(!currentStatus || !TERMINAL.has(currentStatus))
	);
}
