import { redact } from "@src/common/utils/redact";
import { describe, expect, it, vi } from "vitest";

/**
 * PHI-safety wiring tests (GTM-512):
 *  1. The morgan format string uses a PHI-free token set: it logs method, the
 *     path-WITHOUT-query, status and timing — never the request body, headers,
 *     or the raw `:url` (which carries the query string and thus possible PHI).
 *  2. The safe logging path redacts an error that carries PHI (phone/token)
 *     before it reaches jet-logger.
 */

// jet-logger is the sink safeLogger delegates to; capture what actually reaches
// it so we can assert PHI never makes it through.
const { errSpy, warnSpy, infoSpy } = vi.hoisted(() => ({
	errSpy: vi.fn(),
	warnSpy: vi.fn(),
	infoSpy: vi.fn(),
}));

vi.mock("jet-logger", () => ({
	default: { err: errSpy, warn: warnSpy, info: infoSpy },
}));

describe("morgan format (PHI-free token set)", () => {
	it("does not log request body, headers, or the raw url/query", async () => {
		const { MORGAN_FORMAT, morganPathToken } = await import(
			"@src/common/utils/http-security"
		);

		// The :path token strips the query string (PHI may live there).
		expect(morganPathToken({ url: "/api/x?phone=%2B15551234567" })).toBe(
			"/api/x",
		);

		// PHI-free tokens only.
		expect(MORGAN_FORMAT).toContain(":method");
		expect(MORGAN_FORMAT).toContain(":path");
		expect(MORGAN_FORMAT).toContain(":status");

		// Must NOT reference body, query, headers, or the query-bearing :url token.
		expect(MORGAN_FORMAT).not.toContain(":url");
		expect(MORGAN_FORMAT).not.toMatch(/body/i);
		expect(MORGAN_FORMAT).not.toMatch(/query/i);
		expect(MORGAN_FORMAT).not.toMatch(/req\[/);
	});
});

describe("safe error path redacts thrown errors carrying PHI", () => {
	it("scrubs phone/token off an error before logging", async () => {
		const { errorHandler } = await import("@src/common/utils/http-security");
		const HttpStatusCodes = (
			await import("@src/common/constants/HttpStatusCodes")
		).default;

		errSpy.mockClear();

		const err = new Error("unexpected failure for jane@example.com") as Error &
			Record<string, unknown>;
		err.phone = "+15551234567";
		err.token = "super-secret-token";

		const res = {
			headersSent: false,
			statusCode: 200,
			_status: undefined as number | undefined,
			_json: undefined as unknown,
			status(code: number) {
				this._status = code;
				this.statusCode = code;
				return this;
			},
			json(body: unknown) {
				this._json = body;
				return this;
			},
		};
		const next = vi.fn();

		errorHandler(
			err,
			{ method: "POST", headers: {} } as never,
			res as never,
			next as never,
		);

		// Client gets a sanitized 500.
		expect(res._status).toBe(HttpStatusCodes.INTERNAL_SERVER_ERROR);

		// jet-logger must have been called, but with NO PHI in the payload.
		expect(errSpy).toHaveBeenCalledTimes(1);
		const logged = JSON.stringify(errSpy.mock.calls[0]);
		expect(logged).not.toContain("+15551234567");
		expect(logged).not.toContain("super-secret-token");
		expect(logged).not.toContain("jane@example.com");
	});
});

describe("redact integration sanity", () => {
	it("redact() strips a phone/token-bearing error", () => {
		const err = new Error("boom") as Error & Record<string, unknown>;
		err.phone = "+15551234567";
		err.token = "tok";
		const out = JSON.stringify(redact(err));
		expect(out).not.toContain("+15551234567");
		expect(out).not.toContain("tok");
	});
});
