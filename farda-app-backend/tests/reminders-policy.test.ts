import twilio from "twilio";
import { describe, expect, it } from "vitest";
import { inventoryPresentation, receiptDelta } from "../src/refills/service";
import {
	acceptProviderEvent,
	CADENCE,
	DEFAULT_PREFERENCE,
	inQuietHours,
	localDay,
	occurrenceBlock,
	reminderPlan,
	reminderWindowState,
	validTimeZone,
} from "../src/reminders/policy";
import {
	inputTwiml,
	makeVoiceAdapter,
	reminderTwiml,
	validWebhook,
	voiceConfig,
} from "../src/reminders/voice";

const dose = {
	id: "d1",
	userId: "u1",
	scheduledFor: new Date("2026-10-14T16:00:00Z"),
	takenAt: null,
	snoozedUntil: null,
	canceledAt: null,
	status: "unconfirmed",
	updatedAt: new Date(),
};
const pref = { ...DEFAULT_PREFERENCE, timeZone: "America/Los_Angeles" };
describe("reminder timing and gates", () => {
	it("uses the same occurrence for -10 / due / +10 cadence", () => {
		expect(CADENCE.callAfterMinutes).toBe(10);
		expect(reminderPlan(dose).map((p) => p.dueAt.toISOString())).toEqual([
			"2026-10-14T15:50:00.000Z",
			"2026-10-14T16:00:00.000Z",
			"2026-10-14T16:10:00.000Z",
		]);
	});
	it.each([
		["2026-10-14T15:49:59.999Z", "scheduled"],
		["2026-10-14T15:50:00.000Z", "reminder_window"],
		["2026-10-14T16:00:00.000Z", "due_window"],
		["2026-10-14T16:10:00.000Z", "call_window"],
		["2026-10-14T17:00:00.000Z", "closed"],
	])("reports the explicit reminder state at %s", (at, state) => {
		expect(reminderWindowState(dose, new Date(at))).toBe(state);
	});
	it("reports snoozed and resolved states without inferring confirmation", () => {
		expect(
			reminderWindowState(
				{ ...dose, snoozedUntil: new Date("2026-10-14T16:20Z") },
				new Date("2026-10-14T16:10Z"),
			),
		).toBe("snoozed");
		expect(
			reminderWindowState(
				{ ...dose, status: "taken", takenAt: new Date("2026-10-14T16:05Z") },
				new Date("2026-10-14T16:10Z"),
			),
		).toBe("resolved");
	});
	it.each([
		"taken",
		"skipped",
		"cancelled",
	])("suppresses resolved status %s", (status) =>
		expect(
			occurrenceBlock({ ...dose, status }, new Date("2026-10-14T16:10Z")),
		).toBe("occurrence_resolved"));
	it("legacy takenAt blocks even if status is unconfirmed", () =>
		expect(
			occurrenceBlock(
				{ ...dose, takenAt: new Date() },
				new Date("2026-10-14T16:10Z"),
			),
		).toBe("occurrence_resolved"));
	it("does not treat a vial movement observation as a taken record", () => {
		const observed = { ...dose, source: "vial_movement" };
		expect(occurrenceBlock(observed, new Date("2026-10-14T16:10Z"))).toBe(null);
		expect(reminderWindowState(observed, new Date("2026-10-14T16:10Z"))).toBe(
			"call_window",
		);
	});
	it("never sends a late call after an explicit snooze", () =>
		expect(
			occurrenceBlock(
				{ ...dose, snoozedUntil: new Date("2026-10-14T16:05Z") },
				new Date("2026-10-14T16:10Z"),
			),
		).toBe("occurrence_snoozed"));
	it("allows pending occurrence inside window only", () => {
		expect(occurrenceBlock(dose, new Date("2026-10-14T16:10Z"))).toBe(null);
		expect(occurrenceBlock(dose, new Date("2026-10-14T17:00Z"))).toBe(
			"window_expired",
		);
		expect(occurrenceBlock(null, new Date())).toBe("occurrence_missing");
	});
	it("evaluates overnight quiet hours in configured timezone", () => {
		expect(inQuietHours(new Date("2026-10-15T04:00Z"), pref)).toBe(true);
		expect(inQuietHours(new Date("2026-10-15T14:59Z"), pref)).toBe(true);
		expect(inQuietHours(new Date("2026-10-15T15:00Z"), pref)).toBe(false);
	});
	it("handles DST without server-local time assumptions", () => {
		expect(inQuietHours(new Date("2026-11-01T08:30Z"), pref)).toBe(true);
		expect(inQuietHours(new Date("2026-11-01T09:30Z"), pref)).toBe(true);
		expect(localDay(new Date("2026-11-02T07:30Z"), pref.timeZone)).toBe(
			"2026-11-01",
		);
	});
	it("equal quiet-hour endpoints are all-day quiet", () =>
		expect(
			inQuietHours(new Date(), {
				...pref,
				quietHoursStart: "08:00",
				quietHoursEnd: "08:00",
			}),
		).toBe(true));
	it("rejects non-IANA timezone input", () => {
		expect(validTimeZone("America/Los_Angeles")).toBe(true);
		expect(validTimeZone("bad/timezone")).toBe(false);
	});
	it("ignores replay and out-of-order provider updates", () => {
		expect(acceptProviderEvent("ringing", 2, "initiated", 1)).toBe(false);
		expect(acceptProviderEvent("ringing", 2, "ringing", 2)).toBe(false);
		expect(acceptProviderEvent("completed", 3, "ringing", 4)).toBe(false);
		expect(acceptProviderEvent("ringing", 2, "completed", 3)).toBe(true);
		expect(acceptProviderEvent(null, -1, "taken", 0)).toBe(false);
	});
});
describe("voice configuration, privacy and signatures", () => {
	const config = {
		enabled: true,
		accountSid: "AC" + "1".repeat(32),
		authToken: "test-only-token",
		from: "+15551230000",
		publicOrigin: "https://farda.example",
		allowedPrefixes: ["+1"],
		maxCallsPerHour: 20,
	};
	it("is disabled by default, even when OTP credentials exist", async () => {
		const c = voiceConfig({
			TWILIO_ACCOUNT_SID: config.accountSid,
			TWILIO_AUTH_TOKEN: config.authToken,
		});
		expect(c.enabled).toBe(false);
		await expect(makeVoiceAdapter(c).send("a", "+15555550123")).rejects.toThrow(
			"voice_unavailable",
		);
	});
	it("requires explicit enabling, HTTPS origin, calling number and country allowlist", () => {
		const env = {
			FARDA_VOICE_ENABLED: "true",
			TWILIO_ACCOUNT_SID: config.accountSid,
			TWILIO_AUTH_TOKEN: config.authToken,
			FARDA_TWILIO_VOICE_FROM: config.from,
			FARDA_PUBLIC_BASE_URL: config.publicOrigin,
			FARDA_VOICE_ALLOWED_PREFIXES: "+1",
		};
		expect(voiceConfig(env).enabled).toBe(true);
		expect(
			voiceConfig({ ...env, FARDA_PUBLIC_BASE_URL: "http://farda.example" })
				.enabled,
		).toBe(false);
		expect(
			voiceConfig({
				...env,
				FARDA_PUBLIC_BASE_URL: "https://farda.example/api",
			}).enabled,
		).toBe(false);
		expect(
			voiceConfig({ ...env, FARDA_VOICE_ALLOWED_PREFIXES: "" }).enabled,
		).toBe(false);
	});
	it("validates full canonical URL and body with Twilio SDK", () => {
		const path = "/api/reminders/twilio/a/status";
		const body = {
			AccountSid: config.accountSid,
			CallSid: "CA" + "2".repeat(32),
			To: "+15555550123",
			CallStatus: "completed",
			SequenceNumber: "3",
		};
		const signature = twilio.getExpectedTwilioSignature(
			config.authToken,
			config.publicOrigin + path,
			body,
		);
		expect(validWebhook(config, path, signature, body)).toBe(true);
		expect(
			validWebhook(config, path, signature, { ...body, CallStatus: "ringing" }),
		).toBe(false);
		expect(validWebhook(config, path + "?spoof=1", signature, body)).toBe(
			false,
		);
		expect(validWebhook(config, path, undefined, body)).toBe(false);
		expect(
			validWebhook(config, path, signature, { ...body, AccountSid: "foreign" }),
		).toBe(false);
	});
	it("generic reminder plays without a PIN and directs private updates to app", () => {
		const xml = reminderTwiml("https://farda.example/input", "human", true);
		expect(xml).toContain("Your routine is ready");
		expect(xml).toContain("press 9");
		expect(xml).not.toContain("Record");
		expect(xml).not.toContain("PIN");
		expect(inputTwiml("1", true)).toContain("does not log a dose");
	});
	it.each([
		"machine_start",
		"machine_end_beep",
		"fax",
		"unknown",
		undefined,
	])("does not speak to detection %s", (answeredBy) => {
		const xml = reminderTwiml("https://farda.example/input", answeredBy, true);
		expect(xml).toContain("<Hangup");
		expect(xml).not.toContain("<Say");
	});
	it("resolved or revoked calls terminate before the reminder", () =>
		expect(
			reminderTwiml("https://farda.example/input", "human", false),
		).not.toContain("<Say"));
});
describe("inventory semantics", () => {
	it("already counted receipts add zero while preserving receipt quantity", () => {
		expect(receiptDelta(30, true)).toBe(0);
		expect(receiptDelta(30, false)).toBe(30);
	});
	it("reports source/freshness and does not fabricate days remaining", () => {
		const summary = inventoryPresentation(
			{
				quantity: 6,
				observedAt: new Date("2026-10-01"),
				updatedAt: new Date("2026-10-01"),
				revision: 1,
				source: "user_count",
			},
			new Date("2026-10-14"),
		);
		expect(summary.inventory?.stale).toBe(true);
		expect(summary.estimate).toBe(null);
		expect(summary.pharmacyConnected).toBe(false);
		expect(summary.inventory?.automaticallyDecremented).toBe(false);
	});
});
