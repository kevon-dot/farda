import {
	createCorsMiddleware,
	errorHandler,
	parseCorsOrigins,
} from "@src/common/utils/http-security";
import { authRateLimiter, maybeLimiter } from "@src/middleware/rateLimiters";
import BaseRouter from "@src/routes/apiRouter";
import { toNodeHandler } from "better-auth/node";
import express from "express";
import helmet from "helmet";
import morgan from "morgan";
import { auth } from "./auth";
import env from "./common/constants/env";
import Paths from "./common/constants/Paths";

/******************************************************************************
                                Setup
******************************************************************************/

const app = express();

// **** Middleware **** //

// Security headers — applied in ALL environments (#31). The previous
// `NODE_ENV === 'production' && !DISABLE_HELMET` gating meant helmet never ran,
// because the production env file set DISABLE_HELMET=TRUE.
app.use(helmet());

// CORS allowlist (#31). Env-driven via CORS_ORIGINS (comma-separated). No
// wildcard is ever emitted, so authenticated/credentialed routes stay safe;
// only explicitly allowed origins are reflected. Registered BEFORE routes.
app.use(createCorsMiddleware(parseCorsOrigins(env.CORS_ORIGINS)));

// **** better-auth handler (#7/#8/#9) **** //
// Mount the better-auth Node handler on /api/auth/* BEFORE express.json().
// better-auth consumes the RAW request body itself, so the JSON body parser
// must NOT run first (per better-auth's Express integration guidance). It is
// registered after helmet + CORS so security headers and the origin allowlist
// still apply, and before the app routers so it owns the /api/auth namespace.
//
// Re-apply the strict OTP/login limiter (#10) to better-auth's phone-number
// (send-otp / verify) endpoints, restoring the SMS-bombing + brute-force
// throttle that previously sat on the now-removed custom OTP wrapper. Mounted
// before the handler; it runs before express.json(), so the key falls back to
// per-IP (the phone isn't parsed yet) — still the primary abuse defense.
app.use(`${Paths._}/auth/phone-number`, maybeLimiter(authRateLimiter));
app.all(`${Paths._}/auth/*splat`, toNodeHandler(auth));

// Basic middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Show routes called in console during development
if (env.NODE_ENV === "development") {
	app.use(morgan("dev"));
}

// Add APIs, must be after middleware
app.use(Paths._, BaseRouter);

// **** FrontEnd Content **** //
// The express-generator admin HTML page + its `/` and `/users` HTML routes and
// the views/static-file wiring were removed (#35): they rendered the dead
// numeric-id User scaffold. This service is now a JSON API only.

// **** Error handler **** //

// Global error handler — MUST be registered LAST, after all routes (#15/#32).
// Returns clean structured JSON with the correct status for known RouteErrors,
// and a generic sanitized 500 (no message/stack) for unexpected errors.
app.use(errorHandler);

/******************************************************************************
                                Export default
******************************************************************************/

export default app;
