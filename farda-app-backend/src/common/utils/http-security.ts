import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import { RouteError } from "@src/common/utils/route-errors";
import type { NextFunction, Request, RequestHandler, Response } from "express";
import logger from "jet-logger";

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
		logger.warn(`RouteError ${err.status}: ${err.name}`);
		res.status(err.status).json(buildRouteErrorBody(err));
		return;
	}

	// Unexpected error: log full detail server-side, return sanitized response.
	logger.err(err, true);
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
