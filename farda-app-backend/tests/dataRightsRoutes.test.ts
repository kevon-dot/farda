import type { Request, Response } from "express";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Tests for the data-subject rights routes (GTM-542).
 *
 * No live DB: `prisma` is mocked. Verifies auth requirement, IDOR guarding to
 * req.user.id, and the export/deletion request+status happy paths.
 */

const { prismaMock, state } = vi.hoisted(() => {
	const state = {
		exports: [] as Array<Record<string, unknown>>,
		deletions: [] as Array<Record<string, unknown>>,
		consents: [] as Array<Record<string, unknown>>,
	};
	let seq = 0;
	const prismaMock = {
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
					...args.data,
				};
				state.consents.push(row);
				return row;
			}),
			findFirst: vi.fn(async (args: { where: { userId: string } }) => {
				const ms = state.consents
					.filter((c) => c.userId === args.where.userId)
					.sort(
						(a, b) =>
							(b.grantedAt as Date).getTime() - (a.grantedAt as Date).getTime(),
					);
				return ms[0] ?? null;
			}),
		},
		exportRequest: {
			create: vi.fn(async (args: { data: Record<string, unknown> }) => {
				seq += 1;
				const row = {
					id: `exp-${seq}`,
					status: "PENDING",
					format: "json",
					requestedAt: new Date(2026, 5, seq),
					completedAt: null,
					...args.data,
				};
				state.exports.push(row);
				return row;
			}),
			findFirst: vi.fn(async (args: { where: { userId: string } }) => {
				const ms = state.exports
					.filter((e) => e.userId === args.where.userId)
					.sort(
						(a, b) =>
							(b.requestedAt as Date).getTime() -
							(a.requestedAt as Date).getTime(),
					);
				return ms[0] ?? null;
			}),
		},
		deletionRequest: {
			create: vi.fn(async (args: { data: Record<string, unknown> }) => {
				seq += 1;
				const row = {
					id: `del-${seq}`,
					status: "PENDING",
					scope: "FULL",
					triggeredByRevocation: false,
					requestedAt: new Date(2026, 5, seq),
					completedAt: null,
					...args.data,
				};
				state.deletions.push(row);
				return row;
			}),
			findFirst: vi.fn(async (args: { where: { userId: string } }) => {
				const ms = state.deletions
					.filter((d) => d.userId === args.where.userId)
					.sort(
						(a, b) =>
							(b.requestedAt as Date).getTime() -
							(a.requestedAt as Date).getTime(),
					);
				return ms[0] ?? null;
			}),
		},
	};
	return { prismaMock, state };
});

vi.mock("@src/lib/prisma", () => ({ prisma: prismaMock }));

import DataRightsRoutes from "@src/routes/DataRightsRoutes";

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

describe("DataRightsRoutes.requestExport", () => {
	beforeEach(() => {
		state.exports.length = 0;
		state.deletions.length = 0;
		state.consents.length = 0;
		vi.clearAllMocks();
	});

	it("creates a PENDING export request keyed to the session user (201)", async () => {
		const res = makeRes();
		await DataRightsRoutes.requestExport(makeReq(), res);
		expect(res.statusCode).toBe(201);
		const data = prismaMock.exportRequest.create.mock.calls[0][0].data;
		expect(data.userId).toBe("user-1");
	});

	it("ignores any client-supplied userId (IDOR)", async () => {
		const res = makeRes();
		await DataRightsRoutes.requestExport(
			makeReq({ body: { userId: "attacker-999" } }),
			res,
		);
		expect(res.statusCode).toBe(201);
		const data = prismaMock.exportRequest.create.mock.calls[0][0].data;
		expect(data.userId).toBe("user-1");
	});

	it("requires auth (401 with no session user)", async () => {
		const res = makeRes();
		await DataRightsRoutes.requestExport(makeReq({ user: undefined }), res);
		expect(res.statusCode).toBe(401);
		expect(prismaMock.exportRequest.create).not.toHaveBeenCalled();
	});
});

describe("DataRightsRoutes.getExport", () => {
	beforeEach(() => {
		state.exports.length = 0;
		vi.clearAllMocks();
	});

	it("returns the session user's latest export status, scoped to them", async () => {
		await DataRightsRoutes.requestExport(makeReq(), makeRes());
		const res = makeRes();
		await DataRightsRoutes.getExport(makeReq(), res);
		expect(res.statusCode).toBe(200);
		const arg = prismaMock.exportRequest.findFirst.mock.calls[0][0];
		expect(arg.where.userId).toBe("user-1");
	});

	it("requires auth (401)", async () => {
		const res = makeRes();
		await DataRightsRoutes.getExport(makeReq({ user: undefined }), res);
		expect(res.statusCode).toBe(401);
	});
});

describe("DataRightsRoutes.requestDeletion", () => {
	beforeEach(() => {
		state.exports.length = 0;
		state.deletions.length = 0;
		state.consents.length = 0;
		vi.clearAllMocks();
	});

	it("creates a PENDING deletion request keyed to the session user (201)", async () => {
		const res = makeRes();
		await DataRightsRoutes.requestDeletion(makeReq(), res);
		expect(res.statusCode).toBe(201);
		const data = prismaMock.deletionRequest.create.mock.calls[0][0].data;
		expect(data.userId).toBe("user-1");
	});

	it("ignores a client-supplied userId (IDOR)", async () => {
		const res = makeRes();
		await DataRightsRoutes.requestDeletion(
			makeReq({ body: { userId: "attacker-999" } }),
			res,
		);
		expect(res.statusCode).toBe(201);
		const data = prismaMock.deletionRequest.create.mock.calls[0][0].data;
		expect(data.userId).toBe("user-1");
	});

	it("requires auth (401)", async () => {
		const res = makeRes();
		await DataRightsRoutes.requestDeletion(makeReq({ user: undefined }), res);
		expect(res.statusCode).toBe(401);
		expect(prismaMock.deletionRequest.create).not.toHaveBeenCalled();
	});
});

describe("DataRightsRoutes.getDeletion", () => {
	beforeEach(() => {
		state.deletions.length = 0;
		vi.clearAllMocks();
	});

	it("returns the session user's latest deletion status, scoped to them", async () => {
		await DataRightsRoutes.requestDeletion(makeReq(), makeRes());
		const res = makeRes();
		await DataRightsRoutes.getDeletion(makeReq(), res);
		expect(res.statusCode).toBe(200);
		const arg = prismaMock.deletionRequest.findFirst.mock.calls.at(-1)?.[0];
		expect(arg.where.userId).toBe("user-1");
	});

	it("requires auth (401)", async () => {
		const res = makeRes();
		await DataRightsRoutes.getDeletion(makeReq({ user: undefined }), res);
		expect(res.statusCode).toBe(401);
	});
});
