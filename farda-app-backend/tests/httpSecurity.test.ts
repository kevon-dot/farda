import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import {
	createCorsMiddleware,
	errorHandler,
	GENERIC_ERROR_MESSAGE,
	parseCorsOrigins,
} from "@src/common/utils/http-security";
import { RouteError, ValidationError } from "@src/common/utils/route-errors";
import type { NextFunction, Request, Response } from "express";
import { describe, expect, it, vi } from "vitest";

/**
 * Self-contained tests for the security/error-handling middleware (#15/#31/#32).
 * These avoid the database and the Express bootstrap by exercising the pure,
 * exported functions directly with lightweight req/res mocks.
 */

/** Minimal Response mock that records status / json / headers. */
function makeRes(): Response & {
	_status?: number;
	_json?: unknown;
	_headers: Record<string, string>;
	_ended: boolean;
	headersSent: boolean;
} {
	const res = {
		headersSent: false,
		_headers: {} as Record<string, string>,
		_ended: false,
		statusCode: 200,
		status(code: number) {
			this._status = code;
			this.statusCode = code;
			return this;
		},
		json(body: unknown) {
			this._json = body;
			return this;
		},
		setHeader(name: string, value: string) {
			this._headers[name] = value;
			return this;
		},
		end() {
			this._ended = true;
			return this;
		},
	} as unknown as Response & {
		_status?: number;
		_json?: unknown;
		_headers: Record<string, string>;
		_ended: boolean;
		headersSent: boolean;
	};
	return res;
}

function makeReq(overrides: Partial<Request> = {}): Request {
	return {
		method: "GET",
		headers: {},
		...overrides,
	} as Request;
}

/******************************************************************************
                          parseCorsOrigins (#31)
******************************************************************************/

describe("parseCorsOrigins", () => {
	it("returns an empty allowlist for undefined/empty input", () => {
		expect(parseCorsOrigins(undefined)).toEqual([]);
		expect(parseCorsOrigins("")).toEqual([]);
		expect(parseCorsOrigins("  ,  ")).toEqual([]);
	});

	it("splits and trims a comma-separated list", () => {
		expect(
			parseCorsOrigins("https://a.com, https://b.com ,https://c.com"),
		).toEqual(["https://a.com", "https://b.com", "https://c.com"]);
	});
});

/******************************************************************************
                          createCorsMiddleware (#31)
******************************************************************************/

describe("createCorsMiddleware", () => {
	it("reflects an allowed origin and enables credentials (no wildcard)", () => {
		const mw = createCorsMiddleware(["https://app.example.com"]);
		const req = makeReq({
			headers: { origin: "https://app.example.com" },
		});
		const res = makeRes();
		const next = vi.fn();

		mw(req, res, next as unknown as NextFunction);

		expect(res._headers["Access-Control-Allow-Origin"]).toBe(
			"https://app.example.com",
		);
		// Never a wildcard on authenticated routes.
		expect(res._headers["Access-Control-Allow-Origin"]).not.toBe("*");
		expect(res._headers["Access-Control-Allow-Credentials"]).toBe("true");
		expect(next).toHaveBeenCalledTimes(1);
	});

	it("does NOT set CORS headers for a disallowed origin", () => {
		const mw = createCorsMiddleware(["https://app.example.com"]);
		const req = makeReq({ headers: { origin: "https://evil.example.com" } });
		const res = makeRes();
		const next = vi.fn();

		mw(req, res, next as unknown as NextFunction);

		expect(res._headers["Access-Control-Allow-Origin"]).toBeUndefined();
		expect(next).toHaveBeenCalledTimes(1);
	});

	it("short-circuits OPTIONS preflight with 204", () => {
		const mw = createCorsMiddleware(["https://app.example.com"]);
		const req = makeReq({
			method: "OPTIONS",
			headers: { origin: "https://app.example.com" },
		});
		const res = makeRes();
		const next = vi.fn();

		mw(req, res, next as unknown as NextFunction);

		expect(res.statusCode).toBe(HttpStatusCodes.NO_CONTENT);
		expect(res._ended).toBe(true);
		expect(next).not.toHaveBeenCalled();
	});
});

/******************************************************************************
                          errorHandler (#15 / #32)
******************************************************************************/

describe("errorHandler", () => {
	it("returns the RouteError status and its safe message", () => {
		const err = new RouteError(HttpStatusCodes.NOT_FOUND, "User not found");
		const res = makeRes();
		const next = vi.fn();

		errorHandler(err, makeReq(), res, next as unknown as NextFunction);

		expect(res._status).toBe(HttpStatusCodes.NOT_FOUND);
		expect(res._json).toEqual({ error: "User not found" });
		// Must NOT fall through to Express after responding (#15).
		expect(next).not.toHaveBeenCalled();
	});

	it("decodes structured ValidationError messages into clean JSON", () => {
		const zodLike = {
			issues: [{ path: ["x"], message: "Required" }],
		} as never;
		const err = new ValidationError(zodLike);
		const res = makeRes();
		const next = vi.fn();

		errorHandler(err, makeReq(), res, next as unknown as NextFunction);

		expect(res._status).toBe(HttpStatusCodes.BAD_REQUEST);
		const body = res._json as { error: string; errors?: unknown };
		expect(body.error).toBe(ValidationError.MESSAGE);
		expect(Array.isArray(body.errors)).toBe(true);
	});

	it("sanitizes unexpected errors: generic 500, no message/stack leaked", () => {
		const err = new Error("DB connection string postgres://secret@host");
		const res = makeRes();
		const next = vi.fn();

		errorHandler(err, makeReq(), res, next as unknown as NextFunction);

		expect(res._status).toBe(HttpStatusCodes.INTERNAL_SERVER_ERROR);
		expect(res._json).toEqual({ error: GENERIC_ERROR_MESSAGE });
		// The raw message and stack must never reach the client.
		const serialized = JSON.stringify(res._json);
		expect(serialized).not.toContain("postgres://secret");
		expect(serialized).not.toContain("stack");
		expect(next).not.toHaveBeenCalled();
	});

	it("delegates to next when headers were already sent", () => {
		const err = new Error("late failure");
		const res = makeRes();
		res.headersSent = true;
		const next = vi.fn();

		errorHandler(err, makeReq(), res, next as unknown as NextFunction);

		expect(next).toHaveBeenCalledTimes(1);
		expect(res._json).toBeUndefined();
	});
});
