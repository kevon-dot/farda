import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import { assertSameUser } from "@src/common/utils/authorization";
import { RouteError } from "@src/common/utils/route-errors";
import {
	getDeletionStatus,
	getExportStatus,
	requestDeletion,
	requestExport,
} from "@src/services/DataRetentionService";
import type { Request, Response } from "express";

/******************************************************************************
        Data-subject rights routes — export & deletion (GTM-542)
*******************************************************************************

   * POST /api/data/export    -> request a portable export of the user's
                                 identified-layer data (access / portability).
   * GET  /api/data/export    -> the user's latest export request status.
   * POST /api/data/deletion  -> request ERASURE of the user's identified-layer
                                 data. This ALSO revokes the user's consent so no
                                 FUTURE projection occurs (GTM-523 gate).
   * GET  /api/data/deletion  -> the user's latest deletion request status.

  IDOR / A2: the acting user is ALWAYS derived from the validated session
  (req.user.id); we NEVER accept a userId from the client. The router mounts
  `isAuthenticated` (deny-by-default).

  AUDITED: every action writes BOTH an AuditLog entry AND a ProvenanceLedgerEntry
  inside DataRetentionService (PHI-free).

  BOUNDARY: deletion erases the IDENTIFIED layer only. Already-projected
  de-identified / analytic rows are NOT recalled ("can't recall de-identified");
  revocation stops FUTURE projection via the existing consent gate.
******************************************************************************/

function fail(res: Response, error: unknown, fallback: string) {
	if (error instanceof RouteError) {
		return res.status(error.status).json({ error: error.message });
	}
	console.error(fallback, error);
	const message = error instanceof Error ? error.message : fallback;
	return res
		.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
		.json({ error: message });
}

const DataRightsRoutes = {
	/**
	 * POST /api/data/export
	 *
	 * Queue an export of the session user's identified-layer data. Returns the
	 * PENDING request row. The portable payload is assembled on demand by
	 * DataRetentionService.buildExport.
	 */
	requestExport: async (req: Request, res: Response) => {
		try {
			const userId = assertSameUser(req.user?.id, undefined);
			const row = await requestExport(userId);
			return res.status(HttpStatusCodes.CREATED).json({ request: row });
		} catch (error) {
			return fail(res, error, "Failed to request export");
		}
	},

	/**
	 * GET /api/data/export
	 *
	 * The session user's latest export request status (or null).
	 */
	getExport: async (req: Request, res: Response) => {
		try {
			const userId = assertSameUser(req.user?.id, undefined);
			const row = await getExportStatus(userId);
			return res.status(HttpStatusCodes.OK).json({ request: row ?? null });
		} catch (error) {
			return fail(res, error, "Failed to fetch export status");
		}
	},

	/**
	 * POST /api/data/deletion
	 *
	 * Request erasure of the session user's identified-layer data. ALSO revokes
	 * the user's current consent (inside requestDeletion) so the GTM-523 gate
	 * fail-closes future projection. De-identified / analytic rows are NOT
	 * recalled.
	 */
	requestDeletion: async (req: Request, res: Response) => {
		try {
			const userId = assertSameUser(req.user?.id, undefined);
			const row = await requestDeletion(userId, {
				// Direct erasure request (not itself triggered by a revocation), but it
				// DOES revoke consent to stop future projection.
				triggeredByRevocation: false,
				revokeConsentToo: true,
				ip: req.ip ?? null,
				userAgent: req.headers?.["user-agent"] ?? null,
			});
			return res.status(HttpStatusCodes.CREATED).json({ request: row });
		} catch (error) {
			return fail(res, error, "Failed to request deletion");
		}
	},

	/**
	 * GET /api/data/deletion
	 *
	 * The session user's latest deletion request status (or null).
	 */
	getDeletion: async (req: Request, res: Response) => {
		try {
			const userId = assertSameUser(req.user?.id, undefined);
			const row = await getDeletionStatus(userId);
			return res.status(HttpStatusCodes.OK).json({ request: row ?? null });
		} catch (error) {
			return fail(res, error, "Failed to fetch deletion status");
		}
	},
};

export default DataRightsRoutes;
