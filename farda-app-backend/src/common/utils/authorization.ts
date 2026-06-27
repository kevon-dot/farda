import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import { RouteError } from "@src/common/utils/route-errors";

/******************************************************************************
                                Authorization helpers
******************************************************************************/

/**
 * Ensure the acting (session) user matches the resource owner. Used to derive
 * the acting userId from the SESSION and reject any client-supplied id that
 * does not belong to the caller (same-user only; caregiver delegation is out
 * of scope here).
 *
 * Pure function: throws a 403 RouteError on mismatch, otherwise returns the
 * authoritative session userId.
 *
 * @param sessionUserId The user id derived from the validated session.
 * @param requestedUserId The user id supplied by the client (param/body).
 */
export function assertSameUser(
	sessionUserId: string | undefined | null,
	requestedUserId: string | undefined | null,
): string {
	if (!sessionUserId) {
		throw new RouteError(
			HttpStatusCodes.UNAUTHORIZED,
			"Authentication required",
		);
	}

	if (requestedUserId && requestedUserId !== sessionUserId) {
		throw new RouteError(
			HttpStatusCodes.FORBIDDEN,
			"You are not authorized to access this resource",
		);
	}

	return sessionUserId;
}

/**
 * Ensure a loaded resource is owned by the session user. Used for ownership
 * checks where the resource id (e.g. a dose id) is client-supplied and we must
 * confirm it belongs to the caller before mutating it.
 *
 * Pure function: throws a 403 RouteError when the owner differs from the
 * session user, or 404 when the resource was not found.
 *
 * @param sessionUserId The user id derived from the validated session.
 * @param resourceOwnerId The owner userId of the loaded resource (null when the
 *   resource does not exist).
 */
export function assertResourceOwner(
	sessionUserId: string | undefined | null,
	resourceOwnerId: string | undefined | null,
): string {
	if (!sessionUserId) {
		throw new RouteError(
			HttpStatusCodes.UNAUTHORIZED,
			"Authentication required",
		);
	}

	if (!resourceOwnerId) {
		throw new RouteError(HttpStatusCodes.NOT_FOUND, "Resource not found");
	}

	if (resourceOwnerId !== sessionUserId) {
		throw new RouteError(
			HttpStatusCodes.FORBIDDEN,
			"You are not authorized to access this resource",
		);
	}

	return sessionUserId;
}
