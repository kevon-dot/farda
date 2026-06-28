import type { Request, Response } from "express";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Tests for the adherence-metrics route (GTM-540 / GTM-502).
 *
 * No live DB: `prisma` is mocked with `vi.mock` so the suite is deterministic
 * and CI-friendly, matching the project's existing route tests
 * (refillRoutes / reminderRoutes / ocrPersistence).
 */

const { prismaMock } = vi.hoisted(() => {
	const prismaMock = {
		auditLog: {
			findFirst: vi.fn(async () => null),
			create: vi.fn(async (args: { data: Record<string, unknown> }) => ({
				id: "audit-1",
				...args.data,
			})),
		},
		dose: {
			findMany: vi.fn(async () => []),
		},
		prescription: {
			findMany: vi.fn(async () => []),
			findUnique: vi.fn(async () => ({ userId: "user-1" })),
		},
	};
	return { prismaMock };
});

vi.mock("@src/lib/prisma", () => ({ prisma: prismaMock }));

import MetricsRoutes from "@src/routes/MetricsRoutes";

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

/** Build a dose row at 09:00 UTC on day `d` of June 2026. */
function doseRow(day: number, takenOffsetMin: number | null) {
	const scheduledFor = new Date(Date.UTC(2026, 5, day, 9, 0, 0));
	return {
		scheduledFor,
		takenAt:
			takenOffsetMin == null
				? null
				: new Date(scheduledFor.getTime() + takenOffsetMin * 60_000),
	};
}

describe("MetricsRoutes.getAdherence", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		prismaMock.prescription.findUnique.mockResolvedValue({ userId: "user-1" });
	});

	it("returns the 9 adherence metrics (happy path)", async () => {
		prismaMock.dose.findMany.mockResolvedValueOnce([
			doseRow(1, 5),
			doseRow(2, 180),
			doseRow(3, null),
			doseRow(4, 5),
		]);
		prismaMock.prescription.findMany.mockResolvedValueOnce([
			{ medicines: [{ qty: "30" }], doses: [doseRow(1, 5), doseRow(2, 5)] },
		]);

		const res = makeRes();
		await MetricsRoutes.getAdherence(
			makeReq({
				query: {
					start: "2026-06-01T00:00:00.000Z",
					end: "2026-06-14T23:59:59.000Z",
				},
			}),
			res,
		);

		expect(res.statusCode).toBe(200);
		const body = res.body as { metrics: Record<string, unknown> };
		const m = body.metrics;
		// All 9 metrics present (PDC, MPR, doseRates{onTime,missed,late},
		// streaks{current,longest}, timingConsistency, confidenceWeighted).
		expect(m).toHaveProperty("pdc");
		expect(m).toHaveProperty("mpr");
		expect(m).toHaveProperty("doseRates");
		expect(m).toHaveProperty("streaks");
		expect(m).toHaveProperty("timingConsistency");
		expect(m).toHaveProperty("confidenceWeightedAdherence");

		const doseRates = m.doseRates as Record<string, number>;
		expect(doseRates.onTime).toBe(2);
		expect(doseRates.late).toBe(1);
		expect(doseRates.missed).toBe(1);
		const streaks = m.streaks as Record<string, number>;
		expect(streaks.currentStreak).toBe(1);
		expect(streaks.longestStreak).toBe(2);
	});

	it("scopes the dose + prescription queries to the session user", async () => {
		const res = makeRes();
		await MetricsRoutes.getAdherence(makeReq(), res);
		const doseArg = prismaMock.dose.findMany.mock.calls[0][0] as {
			where: { userId: string };
		};
		expect(doseArg.where.userId).toBe("user-1");
		const rxArg = prismaMock.prescription.findMany.mock.calls[0][0] as {
			where: { userId: string };
		};
		expect(rxArg.where.userId).toBe("user-1");
	});

	it("ignores any client-supplied userId (derives from session)", async () => {
		const res = makeRes();
		await MetricsRoutes.getAdherence(
			makeReq({ query: { userId: "attacker-999" } }),
			res,
		);
		expect(res.statusCode).toBe(200);
		const doseArg = prismaMock.dose.findMany.mock.calls[0][0] as {
			where: { userId: string };
		};
		expect(doseArg.where.userId).toBe("user-1");
	});

	it("rejects when there is no session user (401)", async () => {
		const res = makeRes();
		await MetricsRoutes.getAdherence(makeReq({ user: undefined }), res);
		expect(res.statusCode).toBe(401);
		expect(prismaMock.dose.findMany).not.toHaveBeenCalled();
	});

	it("rejects reading metrics scoped to another user's prescription (403 IDOR)", async () => {
		prismaMock.prescription.findUnique.mockResolvedValueOnce({
			userId: "someone-else",
		});
		const res = makeRes();
		await MetricsRoutes.getAdherence(
			makeReq({ query: { prescriptionId: "rx-x" } }),
			res,
		);
		expect(res.statusCode).toBe(403);
		expect(prismaMock.dose.findMany).not.toHaveBeenCalled();
	});

	it("scopes to a prescriptionId the user owns", async () => {
		prismaMock.prescription.findUnique.mockResolvedValueOnce({
			userId: "user-1",
		});
		const res = makeRes();
		await MetricsRoutes.getAdherence(
			makeReq({ query: { prescriptionId: "rx-1" } }),
			res,
		);
		expect(res.statusCode).toBe(200);
		const doseArg = prismaMock.dose.findMany.mock.calls[0][0] as {
			where: { prescriptionId?: string };
		};
		expect(doseArg.where.prescriptionId).toBe("rx-1");
	});

	it("records a READ audit entry for the metrics", async () => {
		const res = makeRes();
		await MetricsRoutes.getAdherence(makeReq(), res);
		const data = (
			prismaMock.auditLog.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(data.action).toBe("READ");
		expect(data.resourceType).toBe("AdherenceMetrics");
	});

	it("rejects an invalid date query (400)", async () => {
		const res = makeRes();
		await MetricsRoutes.getAdherence(
			makeReq({ query: { start: "not-a-date" } }),
			res,
		);
		expect(res.statusCode).toBe(400);
		expect(prismaMock.dose.findMany).not.toHaveBeenCalled();
	});
});
