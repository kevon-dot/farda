import env from "@src/common/constants/env";
import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import type { Request, RequestHandler, Response } from "express";
import rateLimit, { ipKeyGenerator, type Options } from "express-rate-limit";

/******************************************************************************
 * Rate limiting middleware (issue #10)
 *
 * Strict limits on the abuse-prone, cost-bearing endpoints:
 *   - OTP request / OTP verify / login  -> brute-force + SMS-cost surface
 *   - OCR extraction                     -> GPT-4o cost + abuse surface
 *
 * Limiters are exported as a factory + ready-made instances so they can be
 * unit-tested without a live server (see tests/rateLimiters.test.ts) and
 * mounted at the router level in apiRouter.ts (NOT inside handler bodies).
 ******************************************************************************/

/** Safe defaults, used when the matching env var is unset/invalid. */
export const RATE_LIMIT_DEFAULTS = {
	/** Auth (OTP + login): 10 attempts per 15 minutes per key. */
	auth: {
		windowMs: 15 * 60 * 1000,
		max: 10,
	},
	/** OCR extraction: 20 requests per 15 minutes per key. */
	ocr: {
		windowMs: 15 * 60 * 1000,
		max: 20,
	},
} as const;

/** Resolved (env-overridden) limits, computed once at module load. */
export const authRateLimitConfig = {
	windowMs: env.AUTH_RATE_LIMIT_WINDOW_MS ?? RATE_LIMIT_DEFAULTS.auth.windowMs,
	max: env.AUTH_RATE_LIMIT_MAX ?? RATE_LIMIT_DEFAULTS.auth.max,
} as const;

export const ocrRateLimitConfig = {
	windowMs: env.OCR_RATE_LIMIT_WINDOW_MS ?? RATE_LIMIT_DEFAULTS.ocr.windowMs,
	max: env.OCR_RATE_LIMIT_MAX ?? RATE_LIMIT_DEFAULTS.ocr.max,
} as const;

/**
 * Build the IP portion of a rate-limit key in an IPv6-safe way. Bare
 * `req.ip` would let a single IPv6 client rotate through a /64 to evade
 * limits; `ipKeyGenerator` normalises that.
 */
function ipKey(req: Request): string {
	return ipKeyGenerator(req.ip ?? "unknown");
}

/**
 * Auth key: IP + phone number (when present in the body). Keying on phone as
 * well as IP means an attacker can't bypass per-phone throttling just by
 * hopping IPs, and one abusive IP can't lock out unrelated phone numbers.
 */
export function authKeyGenerator(req: Request): string {
	const phone =
		typeof req.body?.phoneNumber === "string" && req.body.phoneNumber.trim()
			? req.body.phoneNumber.trim()
			: "no-phone";
	return `${ipKey(req)}:${phone}`;
}

/**
 * OCR key: IP + user id (when present). Falls back to IP only. `userId` may
 * arrive in the body (save/extract) or params; we check both without reading
 * anything DB-backed so this stays a pure request-derived key.
 */
export function ocrKeyGenerator(req: Request): string {
	const fromBody =
		typeof req.body?.userId === "string" && req.body.userId.trim()
			? req.body.userId.trim()
			: undefined;
	const fromParams =
		typeof req.params?.userId === "string" && req.params.userId.trim()
			? req.params.userId.trim()
			: undefined;
	const user = fromBody ?? fromParams ?? "no-user";
	return `${ipKey(req)}:${user}`;
}

/** Shared 429 responder: clear message; standard headers are set by the lib. */
function makeHandler(message: string): Options["handler"] {
	return (_req: Request, res: Response): void => {
		res.status(HttpStatusCodes.TOO_MANY_REQUESTS).json({
			error: message,
		});
	};
}

/**
 * Factory wrapping express-rate-limit with this project's conventions:
 * `standardHeaders: true` (RateLimit-* draft headers), legacy headers off,
 * and a JSON 429 body. Exposed for tests and reuse.
 */
export function createRateLimiter(opts: {
	windowMs: number;
	max: number;
	message: string;
	keyGenerator?: Options["keyGenerator"];
}): RequestHandler {
	return rateLimit({
		windowMs: opts.windowMs,
		limit: opts.max,
		standardHeaders: true,
		legacyHeaders: false,
		keyGenerator: opts.keyGenerator ?? ((req: Request) => ipKey(req)),
		handler: makeHandler(opts.message),
	});
}

/**
 * Strict limiter for OTP request, OTP verify, and login. Keyed by IP + phone.
 */
export const authRateLimiter: RequestHandler = createRateLimiter({
	windowMs: authRateLimitConfig.windowMs,
	max: authRateLimitConfig.max,
	keyGenerator: authKeyGenerator,
	message:
		"Too many authentication attempts. Please wait a few minutes and try again.",
});

/**
 * Tight limiter for OCR extraction endpoints. Keyed by IP + user id.
 */
export const ocrRateLimiter: RequestHandler = createRateLimiter({
	windowMs: ocrRateLimitConfig.windowMs,
	max: ocrRateLimitConfig.max,
	keyGenerator: ocrKeyGenerator,
	message: "Too many OCR requests. Please wait a few minutes and try again.",
});

/**
 * No-op middleware, used when RATE_LIMIT_DISABLED=true (e.g. local dev / load
 * tests). Mounting code picks between this and the real limiter.
 */
export const noopRateLimiter: RequestHandler = (_req, _res, next) => next();

/** Resolve to the real limiter unless rate limiting is globally disabled. */
export function maybeLimiter(limiter: RequestHandler): RequestHandler {
	return env.RATE_LIMIT_DISABLED ? noopRateLimiter : limiter;
}
