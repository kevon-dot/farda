import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
	ReminderService,
	cancelOccurrenceReminders,
} from "../src/reminders/service";
import {
	DEFAULT_PREFERENCE,
	VOICE_CONSENT_VERSION,
} from "../src/reminders/policy";
import { memoryDb } from "./consumer-memory-db";

const NOW = new Date("2026-10-14T16:10:00Z");
const SID = "CA" + "1".repeat(32);
const config = {
	enabled: true,
	accountSid: "AC" + "1".repeat(32),
	authToken: "test",
	from: "+15555550000",
	publicOrigin: "https://farda.example",
	allowedPrefixes: ["+1"],
	maxCallsPerHour: 20,
};
function fixture() {
	const database = memoryDb({
		user: [
			{ id: "u1", phoneNumber: "+15555550123", phoneNumberVerified: true },
			{ id: "u2", phoneNumber: "+15555550124", phoneNumberVerified: true },
		],
		dose: [
			{
				id: "d1",
				userId: "u1",
				scheduledFor: new Date("2026-10-14T16:00:00Z"),
				status: "unconfirmed",
				takenAt: null,
				snoozedUntil: null,
				canceledAt: null,
				revision: 0,
				updatedAt: NOW,
			},
		],
		reminderPreference: [
			{
				userId: "u1",
				...DEFAULT_PREFERENCE,
				callsEnabled: true,
				timeZone: "America/Los_Angeles",
			},
		],
		channelConsent: [
			{
				id: "consent1",
				userId: "u1",
				channel: "voice",
				phoneNumber: "+15555550123",
				wordingVersion: VOICE_CONSENT_VERSION,
				withdrawnAt: null,
			},
		],
	});
	const adapter = {
		enabled: true,
		send: vi.fn(async () => ({ providerId: SID })),
		cancel: vi.fn(async () => {}),
	};
	const service = new ReminderService(database.db, adapter, config);
	return {
		...database,
		adapter,
		service,
		async plan() {
			await service.plan("u1", "d1");
			return database.rows("reminderIntent").find((r) => r.channel === "voice")!
				.id as string;
		},
	};
}
beforeEach(() => {
	vi.useFakeTimers();
	vi.setSystemTime(NOW);
});
afterEach(() => vi.useRealTimers());
describe("durable reminder dispatch", () => {
	it("shows a planned call only while the currently consented number remains eligible", async () => {
		const f = fixture();
		await f.plan();
		expect((await f.service.occurrence("u1", "d1")).callAt?.toISOString()).toBe(
			"2026-10-14T16:10:00.000Z",
		);
		f.rows("channelConsent")[0].withdrawnAt = NOW;
		expect((await f.service.occurrence("u1", "d1")).callAt).toBe(null);
	});
	it("hides a planned call after the budget is consumed or the number changes", async () => {
		const f = fixture();
		await f.plan();
		f.rows("user")[0].phoneNumber = "+15555550999";
		expect((await f.service.occurrence("u1", "d1")).callAt).toBe(null);
		f.rows("user")[0].phoneNumber = "+15555550123";
		f.rows("deliveryAttempt").push(
			...[1, 2].map((n) => ({
				id: `old-${n}`,
				channel: "voice",
				userId: "u1",
				createdAt: NOW,
			})),
		);
		expect((await f.service.occurrence("u1", "d1")).callAt).toBe(null);
	});
	it("idempotent planning shares a dose without duplicating intents", async () => {
		const f = fixture();
		await f.plan();
		await f.plan();
		expect(f.rows("reminderIntent")).toHaveLength(3);
		expect(new Set(f.rows("reminderIntent").map((i) => i.doseId))).toEqual(
			new Set(["d1"]),
		);
	});
	it("one durable attempt wins concurrent dispatches", async () => {
		const f = fixture(),
			intent = await f.plan();
		await Promise.all([f.service.dispatch(intent), f.service.dispatch(intent)]);
		expect(f.adapter.send).toHaveBeenCalledTimes(1);
		expect(f.rows("deliveryAttempt")).toHaveLength(1);
		expect(f.rows("deliveryAttempt")[0].providerId).toBe(SID);
	});
	it("rechecks cancellation after reservation and before provider call", async () => {
		const f = fixture(),
			intent = await f.plan();
		f.raw.beforeTransaction = async (n: number) => {
			if (n === 2) f.rows("dose")[0].status = "taken";
		};
		await f.service.dispatch(intent);
		expect(f.adapter.send).not.toHaveBeenCalled();
		expect(f.rows("deliveryAttempt")[0].state).toBe("cancelled");
	});
	it("cancels a call if confirmation wins during provider dispatch", async () => {
		const f = fixture(),
			intent = await f.plan();
		f.adapter.send.mockImplementationOnce(async () => {
			f.rows("dose")[0].takenAt = NOW;
			return { providerId: SID };
		});
		await f.service.dispatch(intent);
		expect(f.adapter.cancel).toHaveBeenCalledWith(SID);
	});
	it("uncertain provider acceptance is not retried", async () => {
		const f = fixture(),
			intent = await f.plan();
		f.adapter.send.mockRejectedValueOnce(new Error("network timeout"));
		await f.service.dispatch(intent);
		await f.service.dispatch(intent);
		expect(f.adapter.send).toHaveBeenCalledTimes(1);
		expect(f.rows("deliveryAttempt")[0].state).toBe("uncertain");
	});
	it.each([
		"withdrawn",
		"new_number",
		"unverified",
		"quiet",
		"snoozed",
	])("suppresses %s without provider side effects", async (kind) => {
		const f = fixture(),
			intent = await f.plan();
		if (kind === "withdrawn") f.rows("channelConsent")[0].withdrawnAt = NOW;
		if (kind === "new_number") f.rows("user")[0].phoneNumber = "+15555550999";
		if (kind === "unverified") f.rows("user")[0].phoneNumberVerified = false;
		if (kind === "quiet")
			f.rows("reminderPreference")[0].quietHoursStart = "08:00";
		if (kind === "snoozed")
			f.rows("dose")[0].snoozedUntil = new Date("2026-10-14T16:25Z");
		await f.service.dispatch(intent);
		expect(f.adapter.send).not.toHaveBeenCalled();
		expect(f.rows("reminderIntent").find((i) => i.id === intent)?.state).toBe(
			"cancelled",
		);
	});
	it("counts attempted calls against daily cap including uncertain delivery", async () => {
		const f = fixture(),
			intent = await f.plan();
		f.rows("deliveryAttempt").push(
			...[1, 2].map((n) => ({
				id: `old-${n}`,
				intentId: `other-${n}`,
				channel: "voice",
				userId: "u1",
				state: "uncertain",
				createdAt: new Date("2026-10-14T15:00Z"),
			})),
		);
		await f.service.dispatch(intent);
		expect(f.adapter.send).not.toHaveBeenCalled();
		expect(f.rows("reminderIntent").find((i) => i.id === intent)?.reason).toBe(
			"call_limit",
		);
	});
	it("snooze increments revision and cancels all channel intents", async () => {
		const f = fixture();
		await f.plan();
		const result = await f.service.snooze("u1", "d1", 15, 0);
		expect(result.revision).toBe(1);
		expect(result.snoozedUntil?.toISOString()).toBe("2026-10-14T16:25:00.000Z");
		expect(f.rows("reminderIntent").every((i) => i.state === "cancelled")).toBe(
			true,
		);
		expect(f.rows("dose")[0].takenAt).toBe(null);
	});
	it("foreign user cannot read or snooze occurrence", async () => {
		const f = fixture();
		await expect(f.service.occurrence("u2", "d1")).rejects.toMatchObject({
			status: 404,
		});
		await expect(f.service.snooze("u2", "d1", 15)).rejects.toMatchObject({
			status: 404,
		});
	});
	it("stale snooze revision leaves intents untouched", async () => {
		const f = fixture();
		await f.plan();
		await expect(f.service.snooze("u1", "d1", 15, 8)).rejects.toMatchObject({
			status: 409,
		});
		expect(f.rows("reminderIntent").every((i) => i.state === "pending")).toBe(
			true,
		);
	});
	it("disabled provider produces neither reservation nor fake delivery", async () => {
		const f = fixture(),
			intent = await f.plan();
		f.adapter.enabled = false;
		expect(await f.service.dispatch(intent)).toEqual({ state: "disabled" });
		expect(f.rows("deliveryAttempt")).toHaveLength(0);
	});
});
describe("consent and callbacks", () => {
	it("batch cancellation handles schedule edits without cancelling unrelated occurrences", async () => {
		const f = fixture();
		await f.plan();
		f.rows("dose").push(
			{ ...f.rows("dose")[0], id: "d2" },
			{ ...f.rows("dose")[0], id: "d3" },
		);
		await f.service.plan("u1", "d2");
		await f.service.plan("u1", "d3");
		await f.db.$transaction((tx) =>
			cancelOccurrenceReminders(tx, ["d1", "d2"], "schedule_changed"),
		);
		expect(
			f
				.rows("reminderIntent")
				.filter((i) => ["d1", "d2"].includes(i.doseId))
				.every((i) => i.state === "cancelled"),
		).toBe(true);
		expect(
			f
				.rows("reminderIntent")
				.filter((i) => i.doseId === "d3")
				.every((i) => i.state === "pending"),
		).toBe(true);
	});
	it("empty batch cancellation cannot cancel the account", async () => {
		const f = fixture();
		await f.plan();
		await f.db.$transaction((tx) =>
			cancelOccurrenceReminders(tx, [], "schedule_changed"),
		);
		expect(f.rows("reminderIntent").every((i) => i.state === "pending")).toBe(
			true,
		);
	});
	it("preserves existing consent while editing preferences during provider downtime", async () => {
		const f = fixture();
		f.adapter.enabled = false;
		const result = await f.service.savePreferences("u1", {
			...DEFAULT_PREFERENCE,
			callsEnabled: true,
			quietHoursStart: "22:00",
		});
		expect(result.preferences.quietHoursStart).toBe("22:00");
		expect(result.capabilities.voiceEnabled).toBe(false);
		expect(f.rows("channelConsent")).toHaveLength(1);
	});
	it("reports Live Activity readiness only through the user-scoped resolver", async () => {
		const f = fixture();
		const resolver = vi.fn(async (userId: string) => userId === "u1");
		const service = new ReminderService(f.db, f.adapter, config, resolver);
		expect(
			(await service.preferences("u1")).capabilities
				.liveActivityDeliveryEnabled,
		).toBe(true);
		expect(
			(await service.preferences("u2")).capabilities
				.liveActivityDeliveryEnabled,
		).toBe(false);
		expect(resolver).toHaveBeenCalledWith("u1");
	});
	it("requires distinct consent in addition to phone verification", async () => {
		const f = fixture();
		f.rows("channelConsent").length = 0;
		await expect(
			f.service.savePreferences("u1", {
				...DEFAULT_PREFERENCE,
				callsEnabled: true,
			}),
		).rejects.toMatchObject({ status: 409 });
		await f.service.savePreferences("u1", {
			...DEFAULT_PREFERENCE,
			callsEnabled: true,
			callConsent: true,
			consentVersion: VOICE_CONSENT_VERSION,
		});
		expect(f.rows("channelConsent")).toHaveLength(1);
	});
	it("withdrawal persists and cancels pending attempts", async () => {
		const f = fixture();
		await f.plan();
		await f.service.savePreferences("u1", {
			...DEFAULT_PREFERENCE,
			callsEnabled: false,
		});
		expect(f.rows("channelConsent")[0].withdrawnAt).toEqual(NOW);
		expect(
			f.rows("reminderIntent").find((i) => i.channel === "voice")?.state,
		).toBe("cancelled");
	});
	it("provider completion never confirms dose, replays/out-of-order are harmless", async () => {
		const f = fixture(),
			intent = await f.plan();
		await f.service.dispatch(intent);
		const attempt = f.rows("deliveryAttempt")[0];
		const body = {
			To: "+15555550123",
			CallSid: SID,
			CallStatus: "completed",
			SequenceNumber: "3",
		};
		await f.service.webhook(attempt.id, body, "status");
		await f.service.webhook(attempt.id, body, "status");
		await f.service.webhook(
			attempt.id,
			{ ...body, CallStatus: "ringing", SequenceNumber: "2" },
			"status",
		);
		expect(f.rows("deliveryAttempt")[0].providerStatus).toBe("completed");
		expect(f.rows("dose")[0].status).toBe("unconfirmed");
		expect(f.rows("dose")[0].takenAt).toBe(null);
	});
	it("rejects a valid provider event correlated to the wrong phone or SID", async () => {
		const f = fixture(),
			intent = await f.plan();
		await f.service.dispatch(intent);
		const attempt = f.rows("deliveryAttempt")[0];
		await expect(
			f.service.webhook(
				attempt.id,
				{ To: "+15555550999", CallSid: SID },
				"voice",
			),
		).rejects.toMatchObject({ status: 404 });
		await expect(
			f.service.webhook(
				attempt.id,
				{ To: "+15555550123", CallSid: "CA" + "9".repeat(32) },
				"voice",
			),
		).rejects.toMatchObject({ status: 404 });
	});
	it("keypad 9 opts out without changing a dose", async () => {
		const f = fixture(),
			intent = await f.plan();
		await f.service.dispatch(intent);
		await f.service.webhook(
			f.rows("deliveryAttempt")[0].id,
			{ To: "+15555550123", CallSid: SID, Digits: "9" },
			"input",
		);
		expect(f.rows("reminderPreference")[0].callsEnabled).toBe(false);
		expect(f.rows("dose")[0].status).toBe("unconfirmed");
	});
	it("cancellation helper is safe to repeat inside status transactions", async () => {
		const f = fixture();
		await f.plan();
		await f.db.$transaction((tx) =>
			cancelOccurrenceReminders(tx, "d1", "resolved"),
		);
		await f.db.$transaction((tx) =>
			cancelOccurrenceReminders(tx, "d1", "resolved"),
		);
		expect(f.rows("reminderIntent").every((i) => i.state === "cancelled")).toBe(
			true,
		);
	});
});
