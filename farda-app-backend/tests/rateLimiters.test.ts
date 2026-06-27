import type { Request, Response } from "express";
import { describe, expect, it, vi } from "vitest";
import {
	authKeyGenerator,
	authRateLimitConfig,
	createRateLimiter,
	ocrKeyGenerator,
	ocrRateLimitConfig,
	RATE_LIMIT_DEFAULTS,
} from "../src/middleware/rateLimiters";

/**
 * Self-contained tests for the rate-limiter factory + key generators
 * (issue #10). No live server / DB: we drive the middleware with mock
 * req/res objects through the in-memory store express-rate-limit ships with.
 */

/** Build a minimal mock Request good enough for express-rate-limit. */
function mockReq(overrides: Partial<Request> = {}): Request {
	return {
		ip: "203.0.113.7",
		method: "POST",
		body: {},
		params: {},
		headers: {},
		app: { get: () => undefined },
		...overrides,
	} as unknown as Request;
}

/** Build a mock Response that records status + json payload + headers. */
function mockRes() {
	const res: Record<string, unknown> = {};
	res.statusCode = 200;
	res.headers = {} as Record<string, string>;
	res.status = vi.fn((code: number) => {
		res.statusCode = code;
		return res;
	});
	res.json = vi.fn((body: unknown) => {
		res.body = body;
		return res;
	});
	res.send = vi.fn((body: unknown) => {
		res.body = body;
		return res;
	});
	res.setHeader = vi.fn((name: string, value: unknown) => {
		(res.headers as Record<string, unknown>)[name.toLowerCase()] = value;
		return res;
	});
	res.getHeader = vi.fn(
		(name: string) =>
			(res.headers as Record<string, unknown>)[name.toLowerCase()],
	);
	res.removeHeader = vi.fn();
	res.setHeader = res.setHeader as typeof res.setHeader;
	res.end = vi.fn(() => res);
	return res as unknown as Response & {
		statusCode: number;
		body?: unknown;
		headers: Record<string, unknown>;
	};
}

/**
 * Drive a limiter through `count` sequential requests sharing the same key.
 * Returns the response from the LAST request so the caller can assert on it.
 */
async function hit(
	limiter: ReturnType<typeof createRateLimiter>,
	count: number,
	reqOverrides: Partial<Request> = {},
) {
	let lastRes = mockRes();
	for (let i = 0; i < count; i++) {
		lastRes = mockRes();
		const next = vi.fn();
		await new Promise<void>((resolve) => {
			const maybeNext = (...args: unknown[]) => {
				next(...args);
				resolve();
			};
			// If the limiter short-circuits (429) it never calls next, so we
			// resolve on the json() call instead.
			(lastRes.json as ReturnType<typeof vi.fn>).mockImplementation(
				(body: unknown) => {
					(lastRes as { body?: unknown }).body = body;
					resolve();
					return lastRes;
				},
			);
			limiter(mockReq(reqOverrides), lastRes, maybeNext);
		});
	}
	return lastRes;
}

describe("createRateLimiter (#10)", () => {
	it("allows requests up to the limit then returns 429", async () => {
		const limiter = createRateLimiter({
			windowMs: 60_000,
			max: 3,
			message: "slow down",
		});

		// First 3 should pass straight through to next().
		const allowed = await hit(limiter, 3, { ip: "198.51.100.1" });
		expect(allowed.statusCode).not.toBe(429);

		// 4th exceeds the limit.
		const blocked = await hit(limiter, 1, { ip: "198.51.100.1" });
		expect(blocked.statusCode).toBe(429);
		expect(blocked.body).toEqual({ error: "slow down" });
	});

	it("sets standardized RateLimit-* headers and not legacy X-RateLimit-*", async () => {
		const limiter = createRateLimiter({
			windowMs: 60_000,
			max: 5,
			message: "nope",
		});
		const res = await hit(limiter, 1, { ip: "198.51.100.2" });
		const headerKeys = Object.keys(res.headers);
		expect(headerKeys.some((k) => k.startsWith("ratelimit"))).toBe(true);
		expect(headerKeys.some((k) => k.startsWith("x-ratelimit"))).toBe(false);
	});

	it("keys separate IPs independently", async () => {
		const limiter = createRateLimiter({
			windowMs: 60_000,
			max: 1,
			message: "limit",
		});
		await hit(limiter, 1, { ip: "10.0.0.1" });
		// Different IP -> still allowed on its first request.
		const other = await hit(limiter, 1, { ip: "10.0.0.2" });
		expect(other.statusCode).not.toBe(429);
	});
});

describe("authKeyGenerator (#10)", () => {
	it("combines IP and phone number", () => {
		const key = authKeyGenerator(
			mockReq({ ip: "1.2.3.4", body: { phoneNumber: "+15551234567" } }),
		);
		expect(key).toContain("+15551234567");
		expect(key).toContain("1.2.3.4");
	});

	it("different phones on the same IP produce different keys", () => {
		const a = authKeyGenerator(
			mockReq({ ip: "1.2.3.4", body: { phoneNumber: "+1111" } }),
		);
		const b = authKeyGenerator(
			mockReq({ ip: "1.2.3.4", body: { phoneNumber: "+2222" } }),
		);
		expect(a).not.toEqual(b);
	});

	it("falls back to a no-phone marker when phone is absent", () => {
		const key = authKeyGenerator(mockReq({ ip: "1.2.3.4", body: {} }));
		expect(key).toContain("no-phone");
	});
});

describe("ocrKeyGenerator (#10)", () => {
	it("combines IP and userId from the body", () => {
		const key = ocrKeyGenerator(
			mockReq({ ip: "5.6.7.8", body: { userId: "user-123" } }),
		);
		expect(key).toContain("user-123");
		expect(key).toContain("5.6.7.8");
	});

	it("reads userId from params when not in body", () => {
		const key = ocrKeyGenerator(
			mockReq({ ip: "5.6.7.8", params: { userId: "param-user" } }),
		);
		expect(key).toContain("param-user");
	});

	it("falls back to a no-user marker when userId is absent", () => {
		const key = ocrKeyGenerator(mockReq({ ip: "5.6.7.8" }));
		expect(key).toContain("no-user");
	});
});

describe("resolved config + defaults (#10)", () => {
	it("exposes safe defaults", () => {
		expect(RATE_LIMIT_DEFAULTS.auth.max).toBeGreaterThan(0);
		expect(RATE_LIMIT_DEFAULTS.auth.windowMs).toBeGreaterThan(0);
		expect(RATE_LIMIT_DEFAULTS.ocr.max).toBeGreaterThan(0);
		expect(RATE_LIMIT_DEFAULTS.ocr.windowMs).toBeGreaterThan(0);
	});

	it("resolved configs fall back to defaults when env is unset", () => {
		// The test env sets none of the RATE_LIMIT_* vars, so resolved config
		// must equal the documented defaults.
		expect(authRateLimitConfig.max).toBe(RATE_LIMIT_DEFAULTS.auth.max);
		expect(authRateLimitConfig.windowMs).toBe(
			RATE_LIMIT_DEFAULTS.auth.windowMs,
		);
		expect(ocrRateLimitConfig.max).toBe(RATE_LIMIT_DEFAULTS.ocr.max);
		expect(ocrRateLimitConfig.windowMs).toBe(RATE_LIMIT_DEFAULTS.ocr.windowMs);
	});
});
