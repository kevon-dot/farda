import * as fs from "node:fs";
import * as path from "node:path";
import type { Request, Response } from "express";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Tests for the refill prediction + refill-event routes (GTM-541).
 *
 * No live DB: `prisma` is mocked with `vi.mock` so the suite is deterministic
 * and CI-friendly, matching the project's existing route tests
 * (reminderRoutes / ocrPersistence / auditLog).
 */

const { prismaMock } = vi.hoisted(() => {
	const refillEvents: Array<Record<string, unknown>> = [];
	let seq = 0;
	const prismaMock = {
		__refillEvents: refillEvents,
		auditLog: {
			findFirst: vi.fn(async () => null),
			create: vi.fn(async (args: { data: Record<string, unknown> }) => ({
				id: "audit-1",
				...args.data,
			})),
		},
		prescription: {
			findMany: vi.fn(async () => []),
			findUnique: vi.fn(async () => ({ userId: "user-1" })),
		},
		refillEvent: {
			create: vi.fn(async (args: { data: Record<string, unknown> }) => {
				seq += 1;
				const row = { id: `rfl-${seq}`, ...args.data };
				refillEvents.push(row);
				return row;
			}),
			groupBy: vi.fn(async () => []),
		},
	};
	return { prismaMock };
});

vi.mock("@src/lib/prisma", () => ({ prisma: prismaMock }));

import RefillRoutes from "@src/routes/RefillRoutes";

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

describe("RefillRoutes.getRefills", () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it("computes remaining / days-left / refill-due per prescription", async () => {
		// 30-pill Rx, 1/day schedule, 5 doses taken -> 25 remaining, 25 days left.
		const days: { scheduledFor: Date; takenAt: Date | null }[] = [];
		for (let i = 0; i < 30; i++) {
			days.push({
				scheduledFor: new Date(Date.UTC(2026, 5, 1 + i, 9, 0, 0)),
				takenAt: i < 5 ? new Date(Date.UTC(2026, 5, 1 + i, 9, 5, 0)) : null,
			});
		}
		prismaMock.prescription.findMany.mockResolvedValueOnce([
			{
				id: "rx-1",
				rxNumber: "RX-100",
				storeNumber: "S-7",
				pharmacyOrDoctorName: "Acme",
				medicines: [{ medicineName: "Lisinopril", qty: "30" }],
				doses: days,
			},
		]);

		const res = makeRes();
		await RefillRoutes.getRefills(makeReq(), res);

		expect(res.statusCode).toBe(200);
		const body = res.body as { refills: Array<Record<string, unknown>> };
		expect(body.refills.length).toBe(1);
		const r = body.refills[0];
		expect(r.prescriptionId).toBe("rx-1");
		expect(r.remaining).toBe(25);
		expect(r.remainingSource).toBe("estimated");
		expect(r.dailyRate).toBe(1);
		expect(r.daysLeft).toBe(25);
		expect(r.medicineName).toBe("Lisinopril");
		expect(r.predictedDepletion).toBeTypeOf("string");
		expect(r.refillDue).toBeTypeOf("string");
	});

	it("scopes the query to the session user", async () => {
		const res = makeRes();
		await RefillRoutes.getRefills(makeReq(), res);
		const arg = prismaMock.prescription.findMany.mock.calls[0][0] as {
			where: { userId: string };
		};
		expect(arg.where.userId).toBe("user-1");
	});

	it("rejects when there is no session user (401)", async () => {
		const res = makeRes();
		await RefillRoutes.getRefills(makeReq({ user: undefined }), res);
		expect(res.statusCode).toBe(401);
	});

	it("records a READ audit entry for the prediction", async () => {
		const res = makeRes();
		await RefillRoutes.getRefills(makeReq(), res);
		const data = (
			prismaMock.auditLog.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(data.action).toBe("READ");
		expect(data.resourceType).toBe("RefillPrediction");
	});
});

describe("RefillRoutes.logEvent", () => {
	beforeEach(() => {
		prismaMock.__refillEvents.length = 0;
		vi.clearAllMocks();
		prismaMock.prescription.findUnique.mockResolvedValue({ userId: "user-1" });
	});

	it("logs a REQUESTED event keyed to the session user", async () => {
		const res = makeRes();
		await RefillRoutes.logEvent(
			makeReq({
				body: {
					prescriptionId: "rx-1",
					eventType: "REQUESTED",
					outcome: "manual",
					refillDueDate: "2026-07-20T00:00:00.000Z",
					channel: "MANUAL",
					metadata: { daysLeft: 5 },
				},
			}),
			res,
		);
		expect(res.statusCode).toBe(200);
		const data = (
			prismaMock.refillEvent.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(data.userId).toBe("user-1");
		expect(data.prescriptionId).toBe("rx-1");
		expect(data.eventType).toBe("REQUESTED");
		expect(data.outcome).toBe("manual");
		expect(data.channel).toBe("MANUAL");
		expect(data.refillDueDate).toBeInstanceOf(Date);
	});

	it("derives userId from the session, ignoring any client-supplied userId", async () => {
		const res = makeRes();
		await RefillRoutes.logEvent(
			makeReq({ body: { eventType: "COMPLETED", userId: "attacker-999" } }),
			res,
		);
		expect(res.statusCode).toBe(200);
		const data = (
			prismaMock.refillEvent.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(data.userId).toBe("user-1");
	});

	it("rejects an unknown eventType (400)", async () => {
		const res = makeRes();
		await RefillRoutes.logEvent(makeReq({ body: { eventType: "WAT" } }), res);
		expect(res.statusCode).toBe(400);
		expect(prismaMock.refillEvent.create).not.toHaveBeenCalled();
	});

	it("rejects logging against another user's prescription (403 IDOR)", async () => {
		prismaMock.prescription.findUnique.mockResolvedValueOnce({
			userId: "someone-else",
		});
		const res = makeRes();
		await RefillRoutes.logEvent(
			makeReq({ body: { prescriptionId: "rx-x", eventType: "REQUESTED" } }),
			res,
		);
		expect(res.statusCode).toBe(403);
		expect(prismaMock.refillEvent.create).not.toHaveBeenCalled();
	});

	it("allows a prescriptionId-less (generic) refill event", async () => {
		const res = makeRes();
		await RefillRoutes.logEvent(
			makeReq({ body: { eventType: "DELAYED" } }),
			res,
		);
		expect(res.statusCode).toBe(200);
		expect(prismaMock.prescription.findUnique).not.toHaveBeenCalled();
		const data = (
			prismaMock.refillEvent.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(data.prescriptionId).toBeNull();
	});

	it("does NOT write PHI free-text into the audit log for an event", async () => {
		const res = makeRes();
		await RefillRoutes.logEvent(
			makeReq({ body: { eventType: "COMPLETED", prescriptionId: "rx-1" } }),
			res,
		);
		const data = (
			prismaMock.auditLog.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		const serialized = JSON.stringify(data);
		expect(serialized).not.toMatch(/mood|note|medication|medicineName/i);
		expect(data.resourceType).toBe("RefillEvent");
	});
});

describe("RefillRoutes.getMetrics", () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it("summarises refill-adherence counts + completion rate", async () => {
		prismaMock.refillEvent.groupBy.mockResolvedValueOnce([
			{ eventType: "REQUESTED", _count: { _all: 4 } },
			{ eventType: "COMPLETED", _count: { _all: 3 } },
			{ eventType: "DELAYED", _count: { _all: 1 } },
		]);
		const res = makeRes();
		await RefillRoutes.getMetrics(makeReq(), res);
		expect(res.statusCode).toBe(200);
		const body = res.body as Record<string, unknown>;
		expect(body.requested).toBe(4);
		expect(body.completed).toBe(3);
		expect(body.delayed).toBe(1);
		expect(body.completionRate).toBe(0.75);
	});

	it("returns a null completion rate when nothing was requested", async () => {
		prismaMock.refillEvent.groupBy.mockResolvedValueOnce([]);
		const res = makeRes();
		await RefillRoutes.getMetrics(makeReq(), res);
		const body = res.body as Record<string, unknown>;
		expect(body.requested).toBe(0);
		expect(body.completionRate).toBeNull();
	});
});

describe("refill_prediction migration SQL (GTM-541)", () => {
	const migrationsDir = path.resolve(__dirname, "../prisma/migrations");

	it("creates the RefillEvent table with a SET NULL FK to Prescription", () => {
		const dir = fs
			.readdirSync(migrationsDir)
			.find((d) => d.endsWith("_refill_prediction"));
		expect(dir).toBeTruthy();

		const sql = fs.readFileSync(
			path.join(migrationsDir, dir as string, "migration.sql"),
			"utf8",
		);

		expect(sql).toMatch(/CREATE TABLE (IF NOT EXISTS )?"RefillEvent"/);
		expect(sql).toContain('"eventType"');
		expect(sql).toContain('"refillDueDate"');
		expect(sql).toContain('"channel"');
		// Event FK to Prescription must be ON DELETE SET NULL (events outlive Rx).
		expect(sql).toContain('"RefillEvent_prescriptionId_fkey"');
		expect(sql).toContain("ON DELETE SET NULL");
	});
});
