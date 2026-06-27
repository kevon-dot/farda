import type { NextFunction, Request, Response } from "express";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Auth + ownership tests for the A2 router-level auth / IDOR fix.
 *
 * These run WITHOUT a live database: `prisma` is mocked with `vi.mock` so the
 * suite stays deterministic and CI-friendly (no Postgres / credentials).
 */

// Mock prisma before importing the middleware under test. `vi.hoisted` lets us
// reference the mock fn inside the hoisted `vi.mock` factory.
const { sessionFindUnique } = vi.hoisted(() => ({
	sessionFindUnique: vi.fn(),
}));
vi.mock("@src/lib/prisma", () => ({
	prisma: {
		session: { findUnique: sessionFindUnique },
	},
}));

import {
	assertResourceOwner,
	assertSameUser,
} from "@src/common/utils/authorization";
import { RouteError } from "@src/common/utils/route-errors";
import { isAuthenticated } from "@src/middleware/isAuthenticated";

function makeRes() {
	const res: Partial<Response> & {
		statusCode?: number;
		body?: unknown;
	} = {};
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

describe("isAuthenticated middleware", () => {
	beforeEach(() => {
		sessionFindUnique.mockReset();
	});

	it("returns 401 and does not call next() when no Authorization header", async () => {
		const req = { headers: {} } as unknown as Request;
		const res = makeRes();
		const next = vi.fn() as unknown as NextFunction;

		await isAuthenticated(req, res, next);

		expect(res.statusCode).toBe(401);
		expect(next).not.toHaveBeenCalled();
		expect(sessionFindUnique).not.toHaveBeenCalled();
	});

	it("returns 401 and does not call next() when the bearer token has no session", async () => {
		sessionFindUnique.mockResolvedValue(null);
		const req = {
			headers: { authorization: "Bearer bad-token" },
		} as unknown as Request;
		const res = makeRes();
		const next = vi.fn() as unknown as NextFunction;

		await isAuthenticated(req, res, next);

		expect(res.statusCode).toBe(401);
		expect(next).not.toHaveBeenCalled();
		expect(sessionFindUnique).toHaveBeenCalledOnce();
	});

	it("returns 401 when the session is expired", async () => {
		sessionFindUnique.mockResolvedValue({
			expiresAt: new Date(Date.now() - 1000),
			user: { id: "user-1" },
		});
		const req = {
			headers: { authorization: "Bearer expired" },
		} as unknown as Request;
		const res = makeRes();
		const next = vi.fn() as unknown as NextFunction;

		await isAuthenticated(req, res, next);

		expect(res.statusCode).toBe(401);
		expect(next).not.toHaveBeenCalled();
	});

	it("calls next() and attaches the session user id when the session is valid", async () => {
		sessionFindUnique.mockResolvedValue({
			expiresAt: new Date(Date.now() + 60_000),
			user: { id: "user-1" },
		});
		const req = {
			headers: { authorization: "Bearer good-token" },
		} as unknown as Request;
		const res = makeRes();
		const next = vi.fn() as unknown as NextFunction;

		await isAuthenticated(req, res, next);

		expect(next).toHaveBeenCalledOnce();
		expect(res.status).not.toHaveBeenCalled();
		expect(req.user).toEqual({ id: "user-1" });
	});
});

describe("assertSameUser (IDOR ownership helper)", () => {
	it("returns the session userId when the requested id matches", () => {
		expect(assertSameUser("user-1", "user-1")).toBe("user-1");
	});

	it("returns the session userId when no requested id is supplied", () => {
		expect(assertSameUser("user-1", undefined)).toBe("user-1");
	});

	it("throws a 403 when the requested userId differs from the session", () => {
		try {
			assertSameUser("user-1", "user-2");
			throw new Error("expected assertSameUser to throw");
		} catch (err) {
			expect(err).toBeInstanceOf(RouteError);
			expect((err as RouteError).status).toBe(403);
		}
	});

	it("throws a 401 when there is no session user", () => {
		try {
			assertSameUser(undefined, "user-2");
			throw new Error("expected assertSameUser to throw");
		} catch (err) {
			expect(err).toBeInstanceOf(RouteError);
			expect((err as RouteError).status).toBe(401);
		}
	});
});

describe("assertResourceOwner (dose ownership helper)", () => {
	it("returns the session userId when the resource owner matches", () => {
		expect(assertResourceOwner("user-1", "user-1")).toBe("user-1");
	});

	it("throws a 403 when the resource owner differs from the session user", () => {
		try {
			assertResourceOwner("user-1", "user-2");
			throw new Error("expected assertResourceOwner to throw");
		} catch (err) {
			expect(err).toBeInstanceOf(RouteError);
			expect((err as RouteError).status).toBe(403);
		}
	});

	it("throws a 404 when the resource does not exist (no owner)", () => {
		try {
			assertResourceOwner("user-1", null);
			throw new Error("expected assertResourceOwner to throw");
		} catch (err) {
			expect(err).toBeInstanceOf(RouteError);
			expect((err as RouteError).status).toBe(404);
		}
	});

	it("throws a 401 when there is no session user", () => {
		try {
			assertResourceOwner(undefined, "user-2");
			throw new Error("expected assertResourceOwner to throw");
		} catch (err) {
			expect(err).toBeInstanceOf(RouteError);
			expect((err as RouteError).status).toBe(401);
		}
	});
});
