import { auth } from "@src/auth";
import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import { fromNodeHeaders } from "better-auth/node";
import type { NextFunction, Request, Response } from "express";

/**
 * Router-level auth guard (#7/#8/#9).
 *
 * Sessions are now resolved through better-auth's own API rather than a raw
 * `prisma.session.findUnique` on a bearer token. We pass the incoming request
 * headers (including `Authorization: Bearer <token>` for the mobile client and
 * the session cookie for web) to `auth.api.getSession`; better-auth validates
 * the token/cookie, checks expiry, and returns the session + user.
 *
 * Deny-by-default: any request without a valid session gets a 401. On success
 * we attach `req.user = { id }` exactly as the A2 ownership helpers
 * (`assertSameUser` / `assertResourceOwner`) expect, so those keep working
 * unchanged against the new mechanism.
 */
export const isAuthenticated = async (
	req: Request,
	res: Response,
	next: NextFunction,
) => {
	try {
		const session = await auth.api.getSession({
			headers: fromNodeHeaders(req.headers),
		});

		if (!session?.user?.id) {
			return res
				.status(HttpStatusCodes.UNAUTHORIZED)
				.json({ error: "Unauthorized" });
		}

		// Attach user to request for downstream ownership/IDOR checks.
		req.user = {
			id: session.user.id,
		};

		next();
	} catch (error: any) {
		return res
			.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
			.json({ error: error.message });
	}
};
