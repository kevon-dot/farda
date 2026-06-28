import type { Request, Response } from "express";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Tests for the tiered consent capture routes (GTM-523).
 *
 * No live DB: `prisma` is mocked. Verifies auth requirement, IDOR guarding to
 * req.user.id, and the record/get/history happy paths.
 */

const { prismaMock, state } = vi.hoisted(() => {
	const state: { rows: Array<Record<string, unknown>> } = { rows: [] };
	let seq = 0;
	const prismaMock = {
		__state: state,
		auditLog: {
			findFirst: vi.fn(async () => null),
			create: vi.fn(async (args: { data: Record<string, unknown> }) => ({
				id: "a-1",
				...args.data,
			})),
		},
		provenanceLedgerEntry: {
			findFirst: vi.fn(async () => null),
			create: vi.fn(async (args: { data: Record<string, unknown> }) => ({
				id: "p-1",
				...args.data,
			})),
		},
		consent: {
			create: vi.fn(async (args: { data: Record<string, unknown> }) => {
				seq += 1;
				const row = {
					id: `c-${seq}`,
					grantedAt: new Date(2026, 0, seq),
					revokedAt: null,
					scopes: null,
					purpose: null,
					...args.data,
				};
				state.rows.push(row);
				return row;
			}),
			findFirst: vi.fn(async (args: { where: { userId: string } }) => {
				const ms = state.rows
					.filter((r) => r.userId === args.where.userId)
					.sort(
						(a, b) =>
							(b.grantedAt as Date).getTime() - (a.grantedAt as Date).getTime(),
					);
				return ms[0] ?? null;
			}),
			findMany: vi.fn(async (args: { where: { userId: string } }) =>
				state.rows.filter((r) => r.userId === args.where.userId),
			),
		},
	};
	return { prismaMock, state };
});

vi.mock("@src/lib/prisma", () => ({ prisma: prismaMock }));

import ConsentRoutes from "@src/routes/ConsentRoutes";

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

describe("ConsentRoutes.recordConsent", () => {
	beforeEach(() => {
		state.rows.length = 0;
		vi.clearAllMocks();
	});

	it("records a consent keyed to the session user (201)", async () => {
		const res = makeRes();
		await ConsentRoutes.recordConsent(
			makeReq({
				body: { tier: "RESEARCH", version: "v1", scopes: ["research"] },
			}),
			res,
		);
		expect(res.statusCode).toBe(201);
		const data = (
			prismaMock.consent.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(data.userId).toBe("user-1");
		expect(data.tier).toBe("RESEARCH");
	});

	it("derives userId from the session, ignoring any client-supplied userId (IDOR)", async () => {
		const res = makeRes();
		await ConsentRoutes.recordConsent(
			makeReq({
				body: { tier: "CARE_TEAM", version: "v1", userId: "attacker-999" },
			}),
			res,
		);
		expect(res.statusCode).toBe(201);
		const data = (
			prismaMock.consent.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(data.userId).toBe("user-1");
	});

	it("requires auth (401 with no session user)", async () => {
		const res = makeRes();
		await ConsentRoutes.recordConsent(
			makeReq({ user: undefined, body: { tier: "RESEARCH", version: "v1" } }),
			res,
		);
		expect(res.statusCode).toBe(401);
		expect(prismaMock.consent.create).not.toHaveBeenCalled();
	});

	it("rejects an unknown tier (400)", async () => {
		const res = makeRes();
		await ConsentRoutes.recordConsent(
			makeReq({ body: { tier: "WAT", version: "v1" } }),
			res,
		);
		expect(res.statusCode).toBe(400);
		expect(prismaMock.consent.create).not.toHaveBeenCalled();
	});

	it("rejects a missing version (400)", async () => {
		const res = makeRes();
		await ConsentRoutes.recordConsent(
			makeReq({ body: { tier: "RESEARCH" } }),
			res,
		);
		expect(res.statusCode).toBe(400);
	});
});

describe("ConsentRoutes.getCurrent", () => {
	beforeEach(() => {
		state.rows.length = 0;
		vi.clearAllMocks();
	});

	it("returns the session user's current consent", async () => {
		await ConsentRoutes.recordConsent(
			makeReq({ body: { tier: "RESEARCH", version: "v2" } }),
			makeRes(),
		);
		const res = makeRes();
		await ConsentRoutes.getCurrent(makeReq(), res);
		expect(res.statusCode).toBe(200);
		const body = res.body as { consent: { tier: string } | null };
		expect(body.consent?.tier).toBe("RESEARCH");
		// IDOR: the query is scoped to the session user.
		const arg = prismaMock.consent.findFirst.mock.calls[0][0] as {
			where: { userId: string };
		};
		expect(arg.where.userId).toBe("user-1");
	});

	it("returns null when the user has no consent", async () => {
		const res = makeRes();
		await ConsentRoutes.getCurrent(makeReq({ user: { id: "nobody" } }), res);
		expect(res.statusCode).toBe(200);
		expect((res.body as { consent: unknown }).consent).toBeNull();
	});

	it("requires auth (401)", async () => {
		const res = makeRes();
		await ConsentRoutes.getCurrent(makeReq({ user: undefined }), res);
		expect(res.statusCode).toBe(401);
	});
});

describe("ConsentRoutes.getHistory", () => {
	beforeEach(() => {
		state.rows.length = 0;
		vi.clearAllMocks();
	});

	it("returns the full history scoped to the session user", async () => {
		await ConsentRoutes.recordConsent(
			makeReq({ body: { tier: "CARE_TEAM", version: "v1" } }),
			makeRes(),
		);
		await ConsentRoutes.recordConsent(
			makeReq({ body: { tier: "RESEARCH", version: "v1" } }),
			makeRes(),
		);
		const res = makeRes();
		await ConsentRoutes.getHistory(makeReq(), res);
		expect(res.statusCode).toBe(200);
		const body = res.body as { consents: Array<{ tier: string }> };
		expect(body.consents.length).toBe(2);
		const arg = prismaMock.consent.findMany.mock.calls[0][0] as {
			where: { userId: string };
		};
		expect(arg.where.userId).toBe("user-1");
	});

	it("requires auth (401)", async () => {
		const res = makeRes();
		await ConsentRoutes.getHistory(makeReq({ user: undefined }), res);
		expect(res.statusCode).toBe(401);
	});
});
