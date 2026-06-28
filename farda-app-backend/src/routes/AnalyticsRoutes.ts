import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import { prisma } from "@src/lib/prisma";
import { type AuditAction, recordAccess } from "@src/services/AuditService";
import {
	recordProvenance,
	verifyLedger,
} from "@src/services/ProvenanceService";
import type { Request, Response } from "express";
import { z } from "zod";

/******************************************************************************
        Enterprise analytics export — de-identified / analytic ONLY (GTM-522)
*******************************************************************************

  * GET /api/analytics/metrics            -> analytic-layer metric roll-ups.
  * GET /api/analytics/provenance/verify  -> provenance hash-chain integrity.

  DENY-BY-DEFAULT: the router mounts `isAuthenticated` + `requireAdmin` so only
  an allowlisted admin (ADMIN_USER_IDS) can reach these routes. They serve ONLY
  the de-identified / analytic layers — raw PHI is NEVER exposed here. Every
  access is double-logged: the PHI audit trail (recordAccess) AND the provenance
  ledger (recordProvenance, operation=ACCESS/EXPORT).

  K-ANONYMITY: rows below `minSampleSize` are suppressed so a small-cell metric
  cannot be used to single out an individual.
******************************************************************************/

const MIN_SAMPLE_SIZE = 5;

const MetricsQuerySchema = z.object({
	metric: z.string().max(64).optional(),
	cohort: z.string().max(64).optional(),
	period: z.string().max(32).optional(),
	// Optional override of the k-anonymity floor (cannot go BELOW the default).
	minSampleSize: z.coerce.number().int().min(MIN_SAMPLE_SIZE).optional(),
});

function audit(
	req: Request,
	action: AuditAction,
	resourceType: string,
	metadata?: Record<string, unknown>,
): void {
	void recordAccess({
		actorUserId: req.user?.id ?? null,
		action,
		resourceType,
		resourceId: null,
		ip: req.ip ?? null,
		userAgent: req.headers?.["user-agent"] ?? null,
		metadata: metadata ?? null,
	});
}

const AnalyticsRoutes = {
	/**
	 * GET /api/analytics/metrics
	 *
	 * Returns analytic-layer metric roll-ups (PHI-free). Optional filters by
	 * metric / cohort / period. Rows below the k-anonymity floor are suppressed.
	 */
	getMetrics: async (req: Request, res: Response) => {
		try {
			const parsed = MetricsQuerySchema.safeParse(req.query);
			if (!parsed.success) {
				return res
					.status(HttpStatusCodes.BAD_REQUEST)
					.json({ error: "Invalid query", details: parsed.error });
			}
			const { metric, cohort, period } = parsed.data;
			const minSampleSize = parsed.data.minSampleSize ?? MIN_SAMPLE_SIZE;

			const rows = await prisma.analyticMetric.findMany({
				where: {
					...(metric ? { metric } : {}),
					...(cohort ? { cohort } : {}),
					...(period ? { period } : {}),
					// k-anonymity: never return small-cell rows.
					sampleSize: { gte: minSampleSize },
				},
				orderBy: [{ period: "desc" }, { metric: "asc" }],
				select: {
					metric: true,
					cohort: true,
					period: true,
					value: true,
					sampleSize: true,
				},
			});

			audit(req, "READ", "AnalyticMetric", { count: rows.length });
			void recordProvenance({
				actorUserId: req.user?.id ?? null,
				operation: "EXPORT",
				layer: "ANALYTIC",
				resourceType: "AnalyticMetric",
				metadata: { count: rows.length, minSampleSize },
			});

			return res.status(HttpStatusCodes.OK).json({ metrics: rows });
		} catch (error: unknown) {
			console.error("Error in getMetrics:", error);
			const message =
				error instanceof Error ? error.message : "Failed to fetch metrics";
			return res
				.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
				.json({ error: message });
		}
	},

	/**
	 * GET /api/analytics/provenance/verify
	 *
	 * Verifies the provenance ledger hash chain end-to-end and returns whether
	 * it is intact (admin integrity check). No PHI is returned — only the
	 * verification result.
	 */
	verifyProvenance: async (req: Request, res: Response) => {
		try {
			const result = await verifyLedger();

			audit(req, "READ", "ProvenanceLedgerEntry", {
				valid: result.valid,
				checked: result.checked,
			});
			void recordProvenance({
				actorUserId: req.user?.id ?? null,
				operation: "ACCESS",
				layer: "ANALYTIC",
				resourceType: "ProvenanceLedgerEntry",
				metadata: { valid: result.valid, checked: result.checked },
			});

			return res.status(HttpStatusCodes.OK).json(result);
		} catch (error: unknown) {
			console.error("Error in verifyProvenance:", error);
			const message =
				error instanceof Error ? error.message : "Failed to verify ledger";
			return res
				.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
				.json({ error: message });
		}
	},
};

export default AnalyticsRoutes;
