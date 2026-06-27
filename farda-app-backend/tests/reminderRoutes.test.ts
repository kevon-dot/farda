import * as fs from "node:fs";
import * as path from "node:path";
import type { Request, Response } from "express";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Tests for the reminder + notification engine routes (GTM-537).
 *
 * No live DB: `prisma` is mocked with `vi.mock` so the suite is deterministic
 * and CI-friendly (no Postgres / credentials), matching the project's existing
 * route tests (ocrPersistence / auditLog).
 */

const { prismaMock } = vi.hoisted(() => {
	const reminderEvents: Array<Record<string, unknown>> = [];
	const pushTokens: Array<Record<string, unknown>> = [];
	let seq = 0;
	const prismaMock = {
		__reminderEvents: reminderEvents,
		__pushTokens: pushTokens,
		auditLog: {
			findFirst: vi.fn(async () => null),
			create: vi.fn(async (args: { data: Record<string, unknown> }) => ({
				id: "audit-1",
				...args.data,
			})),
		},
		user: {
			findUnique: vi.fn(async () => ({
				timezone: "America/New_York",
				quietHoursStart: 1320,
				quietHoursEnd: 420,
			})),
			update: vi.fn(async (args: { data: Record<string, unknown> }) => ({
				timezone: args.data.timezone ?? null,
				quietHoursStart: args.data.quietHoursStart ?? null,
				quietHoursEnd: args.data.quietHoursEnd ?? null,
			})),
		},
		dose: {
			findMany: vi.fn(async () => []),
			findUnique: vi.fn(async () => ({ userId: "user-1" })),
		},
		reminderResponseEvent: {
			create: vi.fn(async (args: { data: Record<string, unknown> }) => {
				seq += 1;
				const row = { id: `evt-${seq}`, ...args.data };
				reminderEvents.push(row);
				return row;
			}),
		},
		pushToken: {
			upsert: vi.fn(async (args: { create: Record<string, unknown> }) => {
				seq += 1;
				const row = {
					id: `tok-${seq}`,
					platform: args.create.platform,
					createdAt: new Date(),
				};
				pushTokens.push(row);
				return row;
			}),
		},
	};
	return { prismaMock };
});

vi.mock("@src/lib/prisma", () => ({ prisma: prismaMock }));

import ReminderRoutes from "@src/routes/ReminderRoutes";

function makeRes() {
	const res: Partial<Response> & { statusCode?: number; body?: unknown } = {};
	res.status = vi.fn((code: number) => {
		res.statusCode = code;
		return res as Response;
	}) as unknown as Response["status"];
	res.json = vi.fn((payload: unknown) => {
		res.body = payload;
		return res as Response;
	}) as unknown as Response["json"];
	return res as Response & { statusCode?: number; body?: unknown };
}

function makeReq(
	overrides: Partial<Request> & { user?: { id: string } } = {},
): Request {
	return {
		body: {},
		params: {},
		query: {},
		user: { id: "user-1" },
		ip: "203.0.113.7",
		headers: { "user-agent": "vitest" },
		...overrides,
	} as unknown as Request;
}

describe("ReminderRoutes.getSchedule", () => {
	beforeEach(() => {
		prismaMock.__reminderEvents.length = 0;
		vi.clearAllMocks();
	});

	it("returns the session user's upcoming doses + delivery preferences", async () => {
		prismaMock.dose.findMany.mockResolvedValueOnce([
			{
				id: "dose-1",
				prescriptionId: "rx-1",
				scheduledFor: new Date("2026-07-01T08:00:00Z"),
				prescription: {
					reminderEnabled: true,
					reminderTimes: ["08:00"],
					medicines: [{ medicineName: "Lisinopril" }],
				},
			},
		]);

		const res = makeRes();
		await ReminderRoutes.getSchedule(makeReq(), res);

		expect(res.statusCode).toBe(200);
		const body = res.body as {
			preferences: Record<string, unknown>;
			reminders: Array<Record<string, unknown>>;
		};
		expect(body.reminders.length).toBe(1);
		expect(body.reminders[0].doseId).toBe("dose-1");
		expect(body.reminders[0].medicineName).toBe("Lisinopril");
		expect(body.preferences.timezone).toBe("America/New_York");
		expect(body.preferences.quietHoursStart).toBe(1320);
	});

	it("queries only upcoming, untaken doses for reminder-enabled prescriptions", async () => {
		const res = makeRes();
		await ReminderRoutes.getSchedule(makeReq(), res);

		expect(prismaMock.dose.findMany).toHaveBeenCalledTimes(1);
		const arg = prismaMock.dose.findMany.mock.calls[0][0] as {
			where: Record<string, unknown>;
		};
		expect(arg.where.userId).toBe("user-1");
		expect(arg.where.takenAt).toBeNull();
		expect(arg.where.scheduledFor).toHaveProperty("gte");
		expect(arg.where.prescription).toEqual({ reminderEnabled: true });
	});

	it("rejects when there is no session user (401)", async () => {
		const res = makeRes();
		await ReminderRoutes.getSchedule(makeReq({ user: undefined }), res);
		expect(res.statusCode).toBe(401);
	});

	it("records a READ audit entry for the schedule", async () => {
		const res = makeRes();
		await ReminderRoutes.getSchedule(makeReq(), res);
		expect(prismaMock.auditLog.create).toHaveBeenCalled();
		const data = (
			prismaMock.auditLog.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(data.action).toBe("READ");
		expect(data.resourceType).toBe("ReminderSchedule");
		expect(data.actorUserId).toBe("user-1");
	});
});

describe("ReminderRoutes.logEvent", () => {
	beforeEach(() => {
		prismaMock.__reminderEvents.length = 0;
		vi.clearAllMocks();
		prismaMock.dose.findUnique.mockResolvedValue({ userId: "user-1" });
	});

	it("logs a SNOOZED event keyed to the session user with the expected shape", async () => {
		const res = makeRes();
		await ReminderRoutes.logEvent(
			makeReq({
				body: {
					doseId: "dose-1",
					eventType: "SNOOZED",
					scheduledFor: "2026-07-01T08:00:00.000Z",
					occurredAt: "2026-07-01T08:00:05.000Z",
					snoozeMinutes: 10,
					timeToActionMs: 5000,
					channel: "LOCAL",
					metadata: { platform: "ios" },
				},
			}),
			res,
		);

		expect(res.statusCode).toBe(200);
		expect(prismaMock.reminderResponseEvent.create).toHaveBeenCalledTimes(1);
		const data = (
			prismaMock.reminderResponseEvent.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(data.userId).toBe("user-1");
		expect(data.doseId).toBe("dose-1");
		expect(data.eventType).toBe("SNOOZED");
		expect(data.snoozeMinutes).toBe(10);
		expect(data.timeToActionMs).toBe(5000);
		expect(data.channel).toBe("LOCAL");
		// timestamps coerced to Date.
		expect(data.scheduledFor).toBeInstanceOf(Date);
		expect(data.occurredAt).toBeInstanceOf(Date);
	});

	it("derives userId from the session, ignoring any client-supplied userId", async () => {
		const res = makeRes();
		await ReminderRoutes.logEvent(
			makeReq({
				body: { eventType: "DELIVERED", userId: "attacker-999" },
			}),
			res,
		);
		expect(res.statusCode).toBe(200);
		const data = (
			prismaMock.reminderResponseEvent.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(data.userId).toBe("user-1");
	});

	it("rejects an unknown eventType (400)", async () => {
		const res = makeRes();
		await ReminderRoutes.logEvent(makeReq({ body: { eventType: "WAT" } }), res);
		expect(res.statusCode).toBe(400);
		expect(prismaMock.reminderResponseEvent.create).not.toHaveBeenCalled();
	});

	it("rejects logging an event against another user's dose (403 IDOR)", async () => {
		prismaMock.dose.findUnique.mockResolvedValueOnce({
			userId: "someone-else",
		});
		const res = makeRes();
		await ReminderRoutes.logEvent(
			makeReq({ body: { doseId: "dose-x", eventType: "OPENED" } }),
			res,
		);
		expect(res.statusCode).toBe(403);
		expect(prismaMock.reminderResponseEvent.create).not.toHaveBeenCalled();
	});

	it("allows a doseId-less (generic) reminder event", async () => {
		const res = makeRes();
		await ReminderRoutes.logEvent(
			makeReq({ body: { eventType: "DELIVERED" } }),
			res,
		);
		expect(res.statusCode).toBe(200);
		expect(prismaMock.dose.findUnique).not.toHaveBeenCalled();
		const data = (
			prismaMock.reminderResponseEvent.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(data.doseId).toBeNull();
	});

	it("does NOT write PHI free-text into the audit log for an event", async () => {
		const res = makeRes();
		await ReminderRoutes.logEvent(
			makeReq({ body: { eventType: "ACTIONED", doseId: "dose-1" } }),
			res,
		);
		const data = (
			prismaMock.auditLog.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		const serialized = JSON.stringify(data);
		expect(serialized).not.toMatch(/mood|note|medication|medicineName/i);
		expect(data.resourceType).toBe("ReminderResponseEvent");
	});
});

describe("ReminderRoutes.updatePreferences", () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it("stores timezone + quiet hours for the session user", async () => {
		const res = makeRes();
		await ReminderRoutes.updatePreferences(
			makeReq({
				body: {
					timezone: "Europe/London",
					quietHoursStart: 1320,
					quietHoursEnd: 420,
				},
			}),
			res,
		);
		expect(res.statusCode).toBe(200);
		const arg = prismaMock.user.update.mock.calls[0][0] as {
			where: { id: string };
			data: Record<string, unknown>;
		};
		expect(arg.where.id).toBe("user-1");
		expect(arg.data.timezone).toBe("Europe/London");
		expect(arg.data.quietHoursStart).toBe(1320);
		expect(arg.data.quietHoursEnd).toBe(420);
	});

	it("rejects an out-of-range quiet-hours minute (400)", async () => {
		const res = makeRes();
		await ReminderRoutes.updatePreferences(
			makeReq({ body: { quietHoursStart: 99999 } }),
			res,
		);
		expect(res.statusCode).toBe(400);
		expect(prismaMock.user.update).not.toHaveBeenCalled();
	});
});

describe("ReminderRoutes.registerPushToken (SCAFFOLD)", () => {
	beforeEach(() => {
		prismaMock.__pushTokens.length = 0;
		vi.clearAllMocks();
	});

	it("upserts a token by token value for the session user", async () => {
		const res = makeRes();
		await ReminderRoutes.registerPushToken(
			makeReq({
				body: { token: "fcm-abc", platform: "fcm", deviceId: "device-1" },
			}),
			res,
		);
		expect(res.statusCode).toBe(200);
		expect(prismaMock.pushToken.upsert).toHaveBeenCalledTimes(1);
		const arg = prismaMock.pushToken.upsert.mock.calls[0][0] as {
			where: { token: string };
			create: { userId: string; platform: string };
		};
		expect(arg.where.token).toBe("fcm-abc");
		expect(arg.create.userId).toBe("user-1");
		expect(arg.create.platform).toBe("fcm");
	});

	it("rejects an unknown platform (400)", async () => {
		const res = makeRes();
		await ReminderRoutes.registerPushToken(
			makeReq({ body: { token: "x", platform: "carrier-pigeon" } }),
			res,
		);
		expect(res.statusCode).toBe(400);
		expect(prismaMock.pushToken.upsert).not.toHaveBeenCalled();
	});
});

describe("reminder_engine migration SQL (GTM-537)", () => {
	const migrationsDir = path.resolve(__dirname, "../prisma/migrations");

	it("creates the ReminderResponseEvent + PushToken tables and prefs columns", () => {
		const dir = fs
			.readdirSync(migrationsDir)
			.find((d) => d.endsWith("_reminder_engine"));
		expect(dir).toBeTruthy();

		const sql = fs.readFileSync(
			path.join(migrationsDir, dir as string, "migration.sql"),
			"utf8",
		);

		expect(sql).toMatch(
			/CREATE TABLE (IF NOT EXISTS )?"ReminderResponseEvent"/,
		);
		expect(sql).toMatch(/CREATE TABLE (IF NOT EXISTS )?"PushToken"/);
		// Quiet-hours / timezone columns on User.
		expect(sql).toContain('"timezone"');
		expect(sql).toContain('"quietHoursStart"');
		expect(sql).toContain('"quietHoursEnd"');
		// Per-prescription reminder config.
		expect(sql).toContain('"reminderEnabled"');
		expect(sql).toContain('"reminderTimes"');
		// Event FK to Dose must be ON DELETE SET NULL (events outlive the dose).
		expect(sql).toContain('"ReminderResponseEvent_doseId_fkey"');
		expect(sql).toContain("ON DELETE SET NULL");
		// Push token uniqueness so re-registration upserts cleanly.
		expect(sql).toContain('"PushToken_token_key"');
	});
});
