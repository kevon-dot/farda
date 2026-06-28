import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import { assertSameUser } from "@src/common/utils/authorization";
import { RouteError } from "@src/common/utils/route-errors";
import {
	CONSENT_TIERS,
	getConsentHistory,
	getCurrentConsent,
	recordConsent,
} from "@src/services/ConsentService";
import type { Request, Response } from "express";
import { z } from "zod";

/******************************************************************************
        In-product tiered consent capture routes (GTM-523)
*******************************************************************************

   * POST /api/consent          -> record / update the session user's consent.
   * GET  /api/consent          -> the session user's CURRENT consent.
   * GET  /api/consent/history  -> the session user's full (append-only) history.

  IDOR / A2: the acting user is ALWAYS derived from the validated session
  (req.user.id) — we NEVER accept a userId from the client. Consent is the
  source-of-truth the provenance ledger + data pipeline read to stamp + gate
  every record (see ConsentService / DataPipelineService).

  AUDITED: every consent change writes BOTH an AuditLog entry AND a
  ProvenanceLedgerEntry inside ConsentService.recordConsent (deny-by-default;
  the router mounts `isAuthenticated`).
******************************************************************************/

const RecordConsentSchema = z.object({
	tier: z.enum(CONSENT_TIERS),
	version: z.string().min(1).max(64),
	// NON-PHI labels only (e.g. ["analytics","research"]). Optional.
	scopes: z.array(z.string().max(64)).max(32).optional(),
	purpose: z.string().max(256).optional(),
});

/** Serialise a consent row for the API (omits nothing PHI; all fields non-PHI). */
function serialize(row: {
	id: string;
	tier: string;
	version: string;
	scopes: unknown;
	purpose: string | null;
	grantedAt: Date;
	revokedAt: Date | null;
}) {
	return {
		id: row.id,
		tier: row.tier,
		version: row.version,
		scopes: row.scopes ?? null,
		purpose: row.purpose ?? null,
		grantedAt: row.grantedAt,
		revokedAt: row.revokedAt,
	};
}

const ConsentRoutes = {
	/**
	 * POST /api/consent
	 *
	 * Records (appends) a new consent decision for the session user. Append-only:
	 * the new row becomes the user's current consent; prior rows are untouched.
	 * Writes AuditLog + ProvenanceLedgerEntry via ConsentService.
	 */
	recordConsent: async (req: Request, res: Response) => {
		try {
			// IDOR: derive the user from the session, never the client body.
			const userId = assertSameUser(req.user?.id, undefined);

			const parsed = RecordConsentSchema.safeParse(req.body);
			if (!parsed.success) {
				return res
					.status(HttpStatusCodes.BAD_REQUEST)
					.json({ error: "Invalid consent payload", details: parsed.error });
			}
			const { tier, version, scopes, purpose } = parsed.data;

			const row = await recordConsent({
				userId,
				tier,
				version,
				scopes,
				purpose,
				ip: req.ip ?? null,
				userAgent: req.headers?.["user-agent"] ?? null,
			});

			return res
				.status(HttpStatusCodes.CREATED)
				.json({ consent: serialize(row) });
		} catch (error: unknown) {
			if (error instanceof RouteError) {
				return res.status(error.status).json({ error: error.message });
			}
			console.error("Error in recordConsent:", error);
			const message =
				error instanceof Error ? error.message : "Failed to record consent";
			return res
				.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
				.json({ error: message });
		}
	},

	/**
	 * GET /api/consent
	 *
	 * Returns the session user's CURRENT consent (latest non-revoked), or null.
	 */
	getCurrent: async (req: Request, res: Response) => {
		try {
			const userId = assertSameUser(req.user?.id, undefined);
			const row = await getCurrentConsent(userId);
			return res
				.status(HttpStatusCodes.OK)
				.json({ consent: row ? serialize(row) : null });
		} catch (error: unknown) {
			if (error instanceof RouteError) {
				return res.status(error.status).json({ error: error.message });
			}
			console.error("Error in getCurrent consent:", error);
			const message =
				error instanceof Error ? error.message : "Failed to fetch consent";
			return res
				.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
				.json({ error: message });
		}
	},

	/**
	 * GET /api/consent/history
	 *
	 * Returns the session user's full append-only consent history (newest first),
	 * including revoked rows.
	 */
	getHistory: async (req: Request, res: Response) => {
		try {
			const userId = assertSameUser(req.user?.id, undefined);
			const rows = await getConsentHistory(userId);
			return res
				.status(HttpStatusCodes.OK)
				.json({ consents: rows.map(serialize) });
		} catch (error: unknown) {
			if (error instanceof RouteError) {
				return res.status(error.status).json({ error: error.message });
			}
			console.error("Error in getHistory consent:", error);
			const message =
				error instanceof Error
					? error.message
					: "Failed to fetch consent history";
			return res
				.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
				.json({ error: message });
		}
	},
};

export default ConsentRoutes;
