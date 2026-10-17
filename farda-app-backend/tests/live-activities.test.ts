import { generateKeyPairSync } from "node:crypto";
import { describe, expect, it, vi } from "vitest";
import type { LiveActivityConfig } from "../src/live-activities/apns";
import { liveActivityConfig } from "../src/live-activities/apns";
import { TokenProtector } from "../src/live-activities/crypto";
import { LiveActivityDeliveryService } from "../src/live-activities/service";
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
		await f.service.registerInstallation("owner", input);
		await f.service.registerInstallation("owner", input);
		expect(f.rows("liveActivityInstallation")).toHaveLength(1);
		const stored = f.rows("liveActivityInstallation")[0];
		expect(JSON.stringify(stored)).not.toContain(token);
		expect(stored.userId).toBe("owner");
		await expect(
			f.service.registerInstallation("other", input),
		).rejects.toMatchObject({ status: 409 });
	});

	it("requires occurrence ownership for per-activity registration", async () => {
		const f = fixture();
		await expect(
			f.service.registerActivity("other", {
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
		await f.service.registerInstallation("owner", { installationId, token });
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
			attributes: { occurrenceId: "dose-1" },
			"content-state": { phase: "headsUp", revision: 3 },
		});
		expect(JSON.stringify(payload)).not.toMatch(
			/medication|prescription|taken/i,
		);
		expect(f.rows("liveActivityAttempt")).toHaveLength(1);
	});

	it("does not send a delayed heads-up at or after the due boundary", async () => {
		const f = fixture();
		await f.service.registerInstallation("owner", { installationId, token });
		const result = await f.service.dispatch("intent-before", f.due);
		expect(result).toEqual({ state: "suppressed" });
		expect(f.adapter.send).not.toHaveBeenCalled();
	});

	it("updates only an owned activity token at the due stage", async () => {
		const due = new Date("2026-10-17T13:00:00.000Z");
		const f = fixture(due);
		await f.service.registerActivity("owner", {
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
			disabled.registerInstallation("owner", { installationId, token }),
		).rejects.toMatchObject({ status: 503 });
		expect(f.rows("liveActivityInstallation")).toHaveLength(0);
	});

	it("still revokes registrations and expires stored tokens while delivery is disabled", async () => {
		const f = fixture();
		await f.service.registerInstallation("owner", { installationId, token });
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
		await next.service.registerInstallation("owner", { installationId, token });
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
		await f.service.registerInstallation("owner", { installationId, token });
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
			reason: "live_activity_not_submitted",
		});
	});
});
