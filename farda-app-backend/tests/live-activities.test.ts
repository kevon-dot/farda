import { generateKeyPairSync } from "node:crypto";
import { describe, expect, it, vi } from "vitest";
import type { LiveActivityConfig } from "../src/live-activities/apns";
import {
	ApnsTransportError,
	liveActivityConfig,
	validateLiveActivityPayload,
} from "../src/live-activities/apns";
import { TokenProtector } from "../src/live-activities/crypto";
import {
	LiveActivityDeliveryService,
	queueLiveActivityEnd,
	revokeLiveActivitySession,
} from "../src/live-activities/service";
import { cancelOccurrenceReminders } from "../src/reminders/service";
import { memoryDb } from "./consumer-memory-db";

const token = "ab".repeat(32);
const installationId = "123e4567-e89b-42d3-a456-426614174000";

function enabledConfig(protector: TokenProtector): LiveActivityConfig {
	return {
		enabled: true,
		environment: "development",
		teamId: "ABCDEFGHIJ",
		keyId: "KLMNOPQRST",
		topic: "com.farda.app.push-type.liveactivity",
		privateKey: "unused-by-fake-adapter",
		protector,
	};
}

function fixture(at = new Date("2026-10-17T12:55:00.000Z")) {
	const now = at;
	const due = new Date("2026-10-17T13:00:00.000Z");
	const database = memoryDb({
		user: [{ id: "owner" }, { id: "other" }],
		session: [
			{
				id: "session-owner",
				userId: "owner",
				expiresAt: new Date("2026-12-01T00:00:00.000Z"),
			},
			{
				id: "session-other",
				userId: "other",
				expiresAt: new Date("2026-12-01T00:00:00.000Z"),
			},
		],
		reminderPreference: [{ userId: "owner", liveActivitiesEnabled: true }],
		dose: [
			{
				id: "dose-1",
				userId: "owner",
				scheduledFor: due,
				takenAt: null,
				canceledAt: null,
				snoozedUntil: null,
				status: "unconfirmed",
				revision: 3,
				updatedAt: new Date("2026-10-17T12:40:00.000Z"),
			},
		],
		reminderIntent: [
			{
				id: "intent-before",
				userId: "owner",
				doseId: "dose-1",
				channel: "live_activity",
				stage: "before",
				dueAt: new Date("2026-10-17T12:50:00.000Z"),
				expiresAt: due,
				state: "pending",
			},
		],
	});
	const protector = new TokenProtector(Buffer.alloc(32, 7));
	const adapter = {
		enabled: true,
		send: vi.fn(async () => ({
			accepted: true,
			status: 200,
			invalidateToken: false,
		})),
	};
	const service = new LiveActivityDeliveryService(
		database.db,
		adapter,
		enabledConfig(protector),
		() => now,
	);
	return { ...database, service, adapter, protector, now, due };
}

describe("Live Activity token protection and delivery", () => {
	it("encrypts tokens with context authentication and stable opaque fingerprints", () => {
		const protector = new TokenProtector(Buffer.alloc(32, 1));
		const encrypted = protector.protect(token, "owner:installation");
		expect(encrypted).not.toContain(token);
		expect(protector.unprotect(encrypted, "owner:installation")).toBe(token);
		expect(() => protector.unprotect(encrypted, "other:installation")).toThrow(
			"live_activity_token_unreadable",
		);
		expect(protector.fingerprint(token)).toBe(protector.fingerprint(token));
	});

	it("fails closed unless every APNs and encryption setting is valid", () => {
		const { privateKey } = generateKeyPairSync("ec", {
			namedCurve: "prime256v1",
		});
		const complete = {
			FARDA_LIVE_ACTIVITY_ENABLED: "true",
			FARDA_APNS_ENVIRONMENT: "development",
			FARDA_APNS_TEAM_ID: "ABCDEFGHIJ",
			FARDA_APNS_KEY_ID: "KLMNOPQRST",
			FARDA_APNS_LIVE_ACTIVITY_TOPIC: "com.farda.app.push-type.liveactivity",
			FARDA_APNS_PRIVATE_KEY: privateKey
				.export({
					type: "pkcs8",
					format: "pem",
				})
				.toString(),
			FARDA_LIVE_ACTIVITY_ENCRYPTION_KEY: Buffer.alloc(32, 4).toString(
				"base64",
			),
		};
		expect(liveActivityConfig(complete).enabled).toBe(true);
		for (const missing of Object.keys(complete)) {
			const candidate = { ...complete, [missing]: "" };
			expect(liveActivityConfig(candidate).enabled, missing).toBe(false);
		}
	});

	it("idempotently registers an owned token without storing or returning plaintext", async () => {
		const f = fixture();
		const input = { installationId, token };
		await f.service.registerInstallation("owner", "session-owner", input);
		await f.service.registerInstallation("owner", "session-owner", input);
		expect(f.rows("liveActivityInstallation")).toHaveLength(1);
		const stored = f.rows("liveActivityInstallation")[0];
		expect(JSON.stringify(stored)).not.toContain(token);
		expect(stored.userId).toBe("owner");
		await expect(
			f.service.registerInstallation("other", "session-other", input),
		).rejects.toMatchObject({ status: 409 });
	});

	it("requires occurrence ownership for per-activity registration", async () => {
		const f = fixture();
		await expect(
			f.service.registerActivity("other", "session-other", {
				installationId,
				activityId: "activity-1",
				occurrenceId: "dose-1",
				token,
			}),
		).rejects.toMatchObject({ status: 404 });
		expect(f.rows("liveActivityToken")).toHaveLength(0);
	});

	it("reserves once and submits a private, expiring push-to-start payload", async () => {
		const f = fixture();
		await f.service.registerInstallation("owner", "session-owner", {
			installationId,
			token,
		});
		expect(await f.service.dispatch("intent-before", f.now)).toMatchObject({
			state: "submitted",
			submitted: 1,
		});
		expect(await f.service.dispatch("intent-before", f.now)).toEqual({
			state: "suppressed",
		});
		expect(f.adapter.send).toHaveBeenCalledOnce();
		const [sentToken, payload, expiresAt] = f.adapter.send.mock.calls[0];
		expect(sentToken).toBe(token);
		expect(expiresAt).toEqual(f.due);
		expect(payload.aps).toMatchObject({
			event: "start",
			"attributes-type": "FardaRoutineAttributes",
			"input-push-token": 1,
			attributes: { occurrenceId: "dose-1" },
			"content-state": { phase: "headsUp", revision: 3 },
		});
		expect(() => validateLiveActivityPayload(payload)).not.toThrow();
		expect(JSON.stringify(payload)).not.toMatch(
			/medication|prescription|taken/i,
		);
		expect(f.rows("liveActivityAttempt")).toHaveLength(1);
	});

	it("does not send a delayed heads-up at or after the due boundary", async () => {
		const f = fixture();
		await f.service.registerInstallation("owner", "session-owner", {
			installationId,
			token,
		});
		const result = await f.service.dispatch("intent-before", f.due);
		expect(result).toEqual({ state: "suppressed" });
		expect(f.adapter.send).not.toHaveBeenCalled();
	});

	it("revokes expired-session targets before selecting them for delivery", async () => {
		const f = fixture();
		await f.service.registerInstallation("owner", "session-owner", {
			installationId,
			token,
		});
		f.rows("session")[0].expiresAt = new Date(f.now.getTime() - 60_000);

		expect(await f.service.dispatch("intent-before", f.now)).toEqual({
			state: "suppressed",
		});
		expect(f.adapter.send).not.toHaveBeenCalled();
		expect(f.rows("liveActivityInstallation")[0].revokedAt).toBeInstanceOf(
			Date,
		);
	});

	it("updates only an owned activity token at the due stage", async () => {
		const due = new Date("2026-10-17T13:00:00.000Z");
		const f = fixture(due);
		await f.service.registerActivity("owner", "session-owner", {
			installationId,
			activityId: "activity-1",
			occurrenceId: "dose-1",
			token,
		});
		await f.raw.reminderIntent.create({
			data: {
				id: "intent-due",
				userId: "owner",
				doseId: "dose-1",
				channel: "live_activity",
				stage: "due",
				dueAt: due,
				expiresAt: new Date(due.getTime() + 60 * 60_000),
			},
		});
		await expect(f.service.dispatch("intent-due", due)).resolves.toMatchObject({
			state: "submitted",
			submitted: 1,
		});
		const [, payload, expiresAt] = f.adapter.send.mock.calls[0];
		expect(payload.aps).toMatchObject({
			event: "update",
			"content-state": { phase: "due", revision: 3 },
		});
		expect(payload.aps).not.toHaveProperty("attributes");
		expect(expiresAt).toEqual(new Date(due.getTime() + 60 * 60_000));
	});

	it("does not collect tokens or advertise readiness while APNs is disabled", async () => {
		const f = fixture();
		const disabled = new LiveActivityDeliveryService(
			f.db,
			{ enabled: false, send: vi.fn() },
			{ ...enabledConfig(f.protector), enabled: false },
		);
		expect(await disabled.readyForUser("owner")).toBe(false);
		await expect(
			disabled.registerInstallation("owner", "session-owner", {
				installationId,
				token,
			}),
		).rejects.toMatchObject({ status: 503 });
		expect(f.rows("liveActivityInstallation")).toHaveLength(0);
	});

	it("still revokes registrations and expires stored tokens while delivery is disabled", async () => {
		const f = fixture();
		await f.service.registerInstallation("owner", "session-owner", {
			installationId,
			token,
		});
		const disabled = new LiveActivityDeliveryService(
			f.db,
			{ enabled: false, send: vi.fn() },
			{ ...enabledConfig(f.protector), enabled: false },
			() => new Date("2026-11-18T00:00:00.000Z"),
		);
		await disabled.tick();
		expect(f.rows("liveActivityInstallation")[0].revokedAt).toBeInstanceOf(
			Date,
		);

		const next = fixture();
		await next.service.registerInstallation("owner", "session-owner", {
			installationId,
			token,
		});
		const disabledForNext = new LiveActivityDeliveryService(
			next.db,
			{ enabled: false, send: vi.fn() },
			{ ...enabledConfig(next.protector), enabled: false },
		);
		await disabledForNext.revokeInstallation("owner", installationId);
		expect(next.rows("liveActivityInstallation")[0].revokedAt).toBeInstanceOf(
			Date,
		);
	});

	it("cancels an intent after a definitive provider rejection", async () => {
		const f = fixture();
		await f.service.registerInstallation("owner", "session-owner", {
			installationId,
			token,
		});
		f.adapter.send.mockResolvedValueOnce({
			accepted: false,
			status: 403,
			reason: "InvalidProviderToken",
			invalidateToken: false,
		});
		expect(await f.service.dispatch("intent-before", f.now)).toMatchObject({
			state: "cancelled",
		});
		expect(f.rows("reminderIntent")[0]).toMatchObject({
			state: "cancelled",
			reason: "InvalidProviderToken",
		});
	});

	it("atomically transfers a presented device token to a new authenticated account", async () => {
		const f = fixture();
		const nextInstallation = "223e4567-e89b-42d3-a456-426614174000";
		await f.raw.reminderPreference.create({
			data: { userId: "other", liveActivitiesEnabled: true },
		});
		await f.service.registerInstallation("owner", "session-owner", {
			installationId,
			token,
		});
		await f.service.registerActivity("owner", "session-owner", {
			installationId,
			activityId: "old-account-activity",
			occurrenceId: "dose-1",
			token: "ef".repeat(32),
		});

		await f.service.registerInstallation("other", "session-other", {
			installationId: nextInstallation,
			token,
		});

		expect(f.rows("liveActivityInstallation")).toHaveLength(1);
		expect(f.rows("liveActivityInstallation")[0]).toMatchObject({
			installationId: nextInstallation,
			userId: "other",
			sessionId: "session-other",
			revokedAt: null,
		});
		expect(f.rows("liveActivityToken")).toHaveLength(0);
		expect(JSON.stringify(f.rows("liveActivityInstallation"))).not.toContain(
			token,
		);
	});

	it("revokes only registrations owned by the invalidated session", async () => {
		const f = fixture();
		const otherInstallation = "423e4567-e89b-42d3-a456-426614174000";
		await f.service.registerInstallation("owner", "session-a", {
			installationId,
			token,
		});
		await f.service.registerActivity("owner", "session-a", {
			installationId,
			activityId: "activity-a",
			occurrenceId: "dose-1",
			token: "cd".repeat(32),
		});
		await f.service.registerInstallation("owner", "session-b", {
			installationId: otherInstallation,
			token: "ef".repeat(32),
		});
		await f.service.registerActivity("owner", "session-b", {
			installationId: otherInstallation,
			activityId: "activity-b",
			occurrenceId: "dose-1",
			token: "12".repeat(32),
		});

		await f.db.$transaction((tx) =>
			revokeLiveActivitySession(tx, "owner", "session-a", f.now),
		);

		expect(
			f
				.rows("liveActivityInstallation")
				.find((row) => row.installationId === installationId).revokedAt,
		).toBeInstanceOf(Date);
		expect(
			f
				.rows("liveActivityInstallation")
				.find((row) => row.installationId === otherInstallation).revokedAt,
		).toBeNull();
		expect(
			f.rows("liveActivityToken").find((row) => row.activityId === "activity-a")
				.revokedAt,
		).toBeInstanceOf(Date);
		expect(
			f.rows("liveActivityToken").find((row) => row.activityId === "activity-b")
				.revokedAt,
		).toBeNull();
	});

	it("serializes concurrent registrations of one fingerprint under different IDs", async () => {
		const f = fixture();
		const registrations = await Promise.allSettled([
			f.service.registerInstallation("owner", "session-owner", {
				installationId,
				token,
			}),
			f.service.registerInstallation("owner", "session-owner", {
				installationId: "323e4567-e89b-42d3-a456-426614174000",
				token,
			}),
		]);
		expect(
			registrations.filter((result) => result.status === "fulfilled"),
		).toHaveLength(1);
		const rejected = registrations.find(
			(result) => result.status === "rejected",
		);
		expect(rejected).toMatchObject({ reason: { status: 409 } });
		expect(f.rows("liveActivityInstallation")).toHaveLength(1);
	});

	it("sends authoritative terminal content and retires the activity token", async () => {
		const f = fixture();
		await f.service.registerActivity("owner", "session-owner", {
			installationId,
			activityId: "activity-1",
			occurrenceId: "dose-1",
			token,
		});
		const dose = await f.raw.dose.update({
			where: { id: "dose-1" },
			data: { status: "taken", takenAt: f.now, revision: 4, updatedAt: f.now },
		});
		await f.db.$transaction((tx) => queueLiveActivityEnd(tx, dose, f.now));
		const intent = f
			.rows("reminderIntent")
			.find((candidate) => candidate.stage === "end");

		expect(await f.service.dispatch(intent.id, f.now)).toMatchObject({
			state: "submitted",
			submitted: 1,
		});
		const [, payload] = f.adapter.send.mock.calls[0];
		expect(payload.aps).toMatchObject({
			event: "end",
			"content-state": { phase: "confirmed", revision: 4 },
			"dismissal-date": Math.floor(f.now.getTime() / 1000) + 60,
		});
		expect(f.rows("liveActivityToken")[0].revokedAt).toBeInstanceOf(Date);
		expect(intent.state).toBe("dispatched");
	});

	it("keeps an end intent and its reservation across repeated terminal writes", async () => {
		const f = fixture();
		const dose = await f.raw.dose.update({
			where: { id: "dose-1" },
			data: { status: "taken", takenAt: f.now, revision: 4, updatedAt: f.now },
		});
		await f.db.$transaction(async (tx) => {
			await queueLiveActivityEnd(tx, dose, f.now);
			const end = f
				.rows("reminderIntent")
				.find((candidate) => candidate.stage === "end");
			await tx.liveActivityAttempt.create({
				data: {
					intentId: end.id,
					userId: "owner",
					targetFingerprint: "reserved-end",
					targetKind: "activity",
				},
			});
			await cancelOccurrenceReminders(tx, dose.id, "user_resolved");
			await queueLiveActivityEnd(tx, dose, new Date(f.now.getTime() + 1000));
		});

		const end = f
			.rows("reminderIntent")
			.find((candidate) => candidate.stage === "end");
		expect(end).toMatchObject({ state: "pending", reason: null });
		expect(f.rows("liveActivityAttempt")[0].state).toBe("reserved");
		expect(f.rows("reminderIntent")[0]).toMatchObject({
			stage: "before",
			state: "cancelled",
		});
	});

	it("reopens a previously cancelled end without reopening a dispatched end", async () => {
		const f = fixture();
		const dose = await f.raw.dose.update({
			where: { id: "dose-1" },
			data: { status: "skipped", revision: 4, updatedAt: f.now },
		});
		await f.db.$transaction((tx) => queueLiveActivityEnd(tx, dose, f.now));
		const end = f
			.rows("reminderIntent")
			.find((candidate) => candidate.stage === "end");
		end.state = "cancelled";
		end.reason = "user_resolved";
		await f.db.$transaction((tx) => queueLiveActivityEnd(tx, dose, f.now));
		expect(end).toMatchObject({ state: "pending", reason: null });
		end.state = "dispatched";
		await f.db.$transaction((tx) => queueLiveActivityEnd(tx, dose, f.now));
		expect(end.state).toBe("dispatched");
	});

	it("closes a due intent that has no registered target", async () => {
		const f = fixture();
		expect(await f.service.dispatch("intent-before", f.now)).toEqual({
			state: "suppressed",
		});
		expect(f.rows("reminderIntent")[0]).toMatchObject({
			state: "cancelled",
			reason: "no_live_activity_target",
		});
	});

	it("records local token failures without treating them as ambiguous transport", async () => {
		const f = fixture();
		await f.service.registerInstallation("owner", "session-owner", {
			installationId,
			token,
		});
		f.rows("liveActivityInstallation")[0].tokenCiphertext = "v1.unreadable";
		expect(await f.service.dispatch("intent-before", f.now)).toMatchObject({
			state: "cancelled",
			uncertain: 0,
		});
		expect(f.rows("liveActivityAttempt")[0]).toMatchObject({
			state: "failed",
			reason: "local_token_unreadable",
		});
		expect(f.rows("reminderIntent")[0].state).toBe("cancelled");
		expect(f.rows("liveActivityInstallation")[0].revokedAt).toBeInstanceOf(
			Date,
		);
	});

	it("records only transport uncertainty as an ambiguous submission", async () => {
		const f = fixture();
		await f.service.registerInstallation("owner", "session-owner", {
			installationId,
			token,
		});
		f.adapter.send.mockRejectedValueOnce(new ApnsTransportError());
		expect(await f.service.dispatch("intent-before", f.now)).toMatchObject({
			state: "uncertain",
			uncertain: 1,
		});
		expect(f.rows("liveActivityAttempt")[0]).toMatchObject({
			state: "uncertain",
			reason: "provider_result_unknown",
		});
		expect(f.rows("reminderIntent")[0].state).toBe("dispatched");
	});

	it("does not relabel a known APNs result when outcome persistence fails", async () => {
		const f = fixture();
		await f.service.registerInstallation("owner", "session-owner", {
			installationId,
			token,
		});
		vi.spyOn(
			f.service as never,
			"finishAttempt" as never,
		).mockRejectedValueOnce(new Error("database unavailable") as never);

		expect(await f.service.dispatch("intent-before", f.now)).toMatchObject({
			state: "uncertain",
			uncertain: 1,
		});
		expect(f.adapter.send).toHaveBeenCalledOnce();
		expect(f.rows("liveActivityAttempt")[0]).toMatchObject({
			state: "dispatching",
			reason: null,
		});
	});

	it("atomically closes stale reserved and dispatching attempts with distinct outcomes", async () => {
		const f = fixture();
		await f.raw.reminderIntent.create({
			data: {
				id: "intent-ambiguous",
				userId: "owner",
				doseId: "dose-1",
				channel: "live_activity",
				stage: "due",
				dueAt: f.due,
				expiresAt: new Date(f.due.getTime() + 60 * 60_000),
			},
		});
		const old = new Date(f.now.getTime() - 3 * 60_000);
		await f.raw.liveActivityAttempt.create({
			data: {
				id: "reserved-attempt",
				intentId: "intent-before",
				userId: "owner",
				targetFingerprint: "reserved",
				targetKind: "activity",
				state: "reserved",
				updatedAt: old,
			},
		});
		await f.raw.liveActivityAttempt.create({
			data: {
				id: "dispatching-attempt",
				intentId: "intent-ambiguous",
				userId: "owner",
				targetFingerprint: "dispatching",
				targetKind: "activity",
				state: "dispatching",
				updatedAt: old,
			},
		});

		await f.service.tick(f.now);

		expect(f.rows("liveActivityAttempt")).toEqual(
			expect.arrayContaining([
				expect.objectContaining({
					id: "reserved-attempt",
					state: "failed",
					reason: "worker_interrupted_before_send",
				}),
				expect.objectContaining({
					id: "dispatching-attempt",
					state: "uncertain",
					reason: "provider_result_unknown",
				}),
			]),
		);
		expect(
			f.rows("reminderIntent").find((intent) => intent.id === "intent-before"),
		).toMatchObject({ state: "cancelled" });
		expect(
			f
				.rows("reminderIntent")
				.find((intent) => intent.id === "intent-ambiguous"),
		).toMatchObject({ state: "dispatched" });
	});
});
