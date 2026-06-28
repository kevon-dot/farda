import type { Request, Response } from "express";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Tests for the admin analytics export routes (GTM-522).
 *
 * No live DB: `prisma` is mocked with `vi.mock`. These assert the export serves
 * only the de-identified / analytic layers (PHI-free), applies the k-anonymity
 * floor, and writes both an audit + a provenance entry.
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
		provenanceLedgerEntry: {
			findFirst: vi.fn(async () => null),
			create: vi.fn(async (args: { data: Record<string, unknown> }) => ({
				id: "prov-1",
				...args.data,
			})),
			findMany: vi.fn(async () => []),
		},
		analyticMetric: {
			findMany: vi.fn(async () => [
				{
					metric: "adherence_rate",
					cohort: "California",
					period: "2026-W26",
					value: 0.82,
					sampleSize: 12,
				},
			]),
		},
	};
	return { prismaMock };
});

vi.mock("@src/lib/prisma", () => ({ prisma: prismaMock }));

import AnalyticsRoutes from "@src/routes/AnalyticsRoutes";

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

function makeReq(query: Record<string, unknown> = {}): Request {
	return {
		query,
		params: {},
		body: {},
		user: { id: "admin-1" },
		ip: "203.0.113.7",
		headers: { "user-agent": "vitest" },
	} as unknown as Request;
}

describe("AnalyticsRoutes.getMetrics", () => {
	beforeEach(() => vi.clearAllMocks());

	it("returns analytic-layer rows and applies the k-anonymity floor", async () => {
		const res = makeRes();
		await AnalyticsRoutes.getMetrics(makeReq(), res);

		expect(res.statusCode).toBe(200);
		// The where-clause must include a sampleSize >= floor guard.
		const where = prismaMock.analyticMetric.findMany.mock.calls[0][0].where;
		expect(where.sampleSize).toEqual({ gte: 5 });

		const body = res.body as { metrics: Array<Record<string, unknown>> };
		expect(body.metrics).toHaveLength(1);
		// PHI-free: no subject/user id, no raw identifiers in the payload.
		const serialized = JSON.stringify(body);
		expect(serialized).not.toMatch(/userId|subjectId|email|phone|name/i);
	});

	it("rejects a sub-floor minSampleSize override (validation)", async () => {
		const res = makeRes();
		await AnalyticsRoutes.getMetrics(makeReq({ minSampleSize: "1" }), res);
		expect(res.statusCode).toBe(400);
	});

	it("writes both an audit and a provenance EXPORT entry", async () => {
		const res = makeRes();
		await AnalyticsRoutes.getMetrics(makeReq(), res);

		expect(prismaMock.auditLog.create).toHaveBeenCalledTimes(1);
		expect(prismaMock.provenanceLedgerEntry.create).toHaveBeenCalledTimes(1);
		const prov = prismaMock.provenanceLedgerEntry.create.mock.calls[0][0].data;
		expect(prov.operation).toBe("EXPORT");
		expect(prov.layer).toBe("ANALYTIC");
	});
});

describe("AnalyticsRoutes.verifyProvenance", () => {
	beforeEach(() => vi.clearAllMocks());

	it("returns a valid result for an empty/intact ledger", async () => {
		const res = makeRes();
		await AnalyticsRoutes.verifyProvenance(makeReq(), res);
		expect(res.statusCode).toBe(200);
		expect((res.body as { valid: boolean }).valid).toBe(true);
	});
});
