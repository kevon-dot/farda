import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import type { NextFunction, Request, Response } from "express";

/**
 * Admin allowlist sourced from the ADMIN_USER_IDS env var (comma-separated
 * better-auth user ids). Empty/unset means NO user is an admin, so the
 * protected route is effectively locked down until an operator opts an id in.
 */
function getAdminUserIds(): Set<string> {
	// eslint-disable-next-line no-process-env
	const raw = process.env.ADMIN_USER_IDS ?? "";
	return new Set(
		raw
			.split(",")
			.map((id) => id.trim())
			.filter((id) => id.length > 0),
	);
}

/**
 * Admin-lock middleware. Must run AFTER `isAuthenticated` (it relies on
 * `req.user.id`). Denies any user that is not on the admin allowlist.
 */
export const requireAdmin = (
	req: Request,
	res: Response,
	next: NextFunction,
) => {
	const userId = req.user?.id;

	if (!userId) {
		return res
			.status(HttpStatusCodes.UNAUTHORIZED)
			.json({ error: "Authentication required" });
	}

	if (!getAdminUserIds().has(userId)) {
		return res
			.status(HttpStatusCodes.FORBIDDEN)
			.json({ error: "Admin access required" });
	}

	return next();
};
