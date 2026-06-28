import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import { RouteError } from "@src/common/utils/route-errors";
import { logErr, logWarn } from "@src/common/utils/safeLogger";
import type { NextFunction, Request, RequestHandler, Response } from "express";

/******************************************************************************
                                Types
******************************************************************************/

interface SanitizedErrorBody {
	error: string;
	errors?: unknown;
}

/******************************************************************************
                               CORS (#31)
******************************************************************************/

/**
 * Generic, sanitized message returned to clients for unexpected (non-RouteError)
 * failures. We never expose `error.message` or stack traces for these (#32).
 */
export const GENERIC_ERROR_MESSAGE = "An unexpected error occurred.";

/**
 * PHI-safe morgan log format (GTM-512). The default `dev`/`combined` formats log
 * `:url`, which includes the query string and can carry PHI (e.g. ?phone=,
 * ?email=). This format logs a PHI-free token set only — method, the
 * PATH-WITHOUT-QUERY (`:path`, see {@link morganPathToken}), status, response
 * size and timing. It never logs the request body, headers, or the raw `:url`.
 */
export const MORGAN_FORMAT =
	":method :path :status :res[content-length] - :response-time ms";

/**
 * Custom morgan `:path` token: the request URL with the query string stripped,
 * so PHI carried in query params is never written to the access log.
 */
export function morganPathToken(req: { url?: string }): string {
	const url = req.url ?? "";
	const queryIndex = url.indexOf("?");
	return queryIndex === -1 ? url : url.slice(0, queryIndex);
}

/**
 * Parse a comma/space separated list of allowed CORS origins from an env value.
 * Empty/undefined yields an empty allowlist (no cross-origin access granted).
 */
export function parseCorsOrigins(raw?: string): string[] {
	if (!raw) {
		return [];
	}
	return raw
		.split(",")
		.map((o) => o.trim())
		.filter((o) => o.length > 0);
}

/**
 * Build a CORS middleware backed by an explicit allowlist. We deliberately do
 * NOT emit a wildcard `*` for authenticated routes: only origins present in the
 * allowlist are reflected, and credentials are enabled so cookies/Authorization
 * headers work for the allowed origins.
 */
export function createCorsMiddleware(allowedOrigins: string[]): RequestHandler {
	const allowSet = new Set(allowedOrigins);

	return (req: Request, res: Response, next: NextFunction): void => {
		const origin = req.headers.origin;

		if (origin && allowSet.has(origin)) {
			res.setHeader("Access-Control-Allow-Origin", origin);
			res.setHeader("Access-Control-Allow-Credentials", "true");
			res.setHeader("Vary", "Origin");
			res.setHeader(
				"Access-Control-Allow-Methods",
				"GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS",
			);
			res.setHeader(
				"Access-Control-Allow-Headers",
				"Content-Type,Authorization",
			);
		}

		// Short-circuit preflight requests.
		if (req.method === "OPTIONS") {
			// 204 No Content for preflight; headers above (if origin allowed) suffice.
			res.statusCode = HttpStatusCodes.NO_CONTENT;
			res.end();
			return;
		}

		next();
	};
}

/******************************************************************************
                          Error handler (#15 / #32)
******************************************************************************/

/**
 * Pure, testable global error handler.
 *
 * - Known `RouteError`s keep their intended status and safe message (#15) so
 *   client-facing 4xx validation errors stay specific.
 * - Unexpected errors are sanitized: a generic message + 500 is returned to the
 *   client, while the full error is logged server-side only (#32). We never
 *   leak `error.message` or the stack to the response for these.
 * - It is a correct 4-arg Express error middleware and does NOT call `next(err)`
 *   after sending a response (fixes the "headers already sent" fall-through to
 *   Express's HTML stack-trace page).
 */
export function errorHandler(
	err: unknown,
	_req: Request,
	res: Response,
	next: NextFunction,
): void {
	// If a response has already started streaming, delegate to Express' default
	// handler which will simply close the connection.
	if (res.headersSent) {
		next(err);
		return;
	}

	if (err instanceof RouteError) {
		// Known, client-safe error. Log non-PHI metadata only (status + name).
		logWarn(`RouteError ${err.status}: ${err.name}`);
		res.status(err.status).json(buildRouteErrorBody(err));
		return;
	}

	// Unexpected error: log redacted detail server-side (an unexpected error can
	// carry PHI in its message/stack or hung-off props), return sanitized response.
	logErr(err);
	res.status(HttpStatusCodes.INTERNAL_SERVER_ERROR).json({
		error: GENERIC_ERROR_MESSAGE,
	});
}

/**
 * Some RouteErrors (notably ValidationError) carry a JSON-encoded message with a
 * structured `errors` array. Decode it so the client receives clean structured
 * JSON instead of a stringified blob, while still never exposing internals.
 */
function buildRouteErrorBody(err: RouteError): SanitizedErrorBody {
	try {
		const parsed = JSON.parse(err.message);
		if (parsed && typeof parsed === "object" && "message" in parsed) {
			const body: SanitizedErrorBody = {
				error: String((parsed as { message: unknown }).message),
			};
			if ("errors" in parsed) {
				body.errors = (parsed as { errors: unknown }).errors;
			}
			return body;
		}
	} catch {
		// Not JSON; fall through to plain message.
	}
	return { error: err.message };
}
