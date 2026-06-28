import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import {
	assertResourceOwner,
	assertSameUser,
} from "@src/common/utils/authorization";
import { RouteError } from "@src/common/utils/route-errors";
import { prisma } from "@src/lib/prisma";
import {
	type AdherenceMetrics,
	computeAdherenceMetrics,
	type DoseEvent,
	type InventoryInput,
} from "@src/services/AdherenceMetricsService";
import { type AuditAction, recordAccess } from "@src/services/AuditService";
import { dailyRateFromSchedule, parseQty } from "@src/services/RefillService";
import type { Request, Response } from "express";
import { z } from "zod";

/******************************************************************************
        Adherence-metrics routes (GTM-540 / GTM-502)
*******************************************************************************

   * GET /api/metrics/adherence -> the 9 adherence metrics for the session user
                                   over an optional date range, derived on read
                                   from their Dose rows + Rx/Medicine inventory.
                                   Optional query: start, end, prescriptionId.

  IDOR / A2: the acting user is ALWAYS derived from the validated session
  (req.user.id) — we NEVER accept a userId from the client. When a prescriptionId
  is supplied we confirm it belongs to the session user before scoping to it. The
  metric math itself lives in the pure, testable AdherenceMetricsService.

  GTM-520 SEAM: dose-event `confidence` defaults to 1.0 (the confidence engine is
  not built yet). When it lands it can map a per-dose score onto DoseEvent and
  metric 9 (confidence-weighted adherence) starts using it with no route change.
******************************************************************************/

/** Default look-back window (days) when no range is supplied. */
const DEFAULT_WINDOW_DAYS = 30;

const QuerySchema = z.object({
	// Inclusive window bounds (ISO). Optional — defaults to the last 30 days.
	start: z.string().datetime().optional(),
	end: z.string().datetime().optional(),
	// Optional: scope the metrics to a single prescription (IDOR-checked).
	prescriptionId: z.string().optional(),
	// Optional on-time tolerance override (minutes).
	onTimeWindowMinutes: z.coerce.number().int().positive().max(720).optional(),
});

/**
 * One-line audit helper mirroring RefillRoutes/ReminderRoutes.audit: records
 * ids/types/action + request metadata only (never PHI), never throws/blocks.
 */
function audit(
	req: Request,
	action: AuditAction,
	resourceType: string,
	resourceId?: string | null,
	metadata?: Record<string, unknown>,
): void {
	void recordAccess({
		actorUserId: req.user?.id ?? null,
		action,
		resourceType,
		resourceId: resourceId ?? null,
		ip: req.ip ?? null,
		userAgent: req.headers?.["user-agent"] ?? null,
		metadata: metadata ?? null,
	});
}

const MetricsRoutes = {
	/**
	 * GET /api/metrics/adherence
	 *
	 * Returns the authenticated user's 9 adherence metrics over the requested
	 * window. Doses (scheduledFor/takenAt) and inventory (Medicine.qty + the
	 * schedule-derived daily rate) are pulled for the session user only; the pure
	 * AdherenceMetricsService does all the math.
	 */
	getAdherence: async (req: Request, res: Response) => {
		try {
			const userId = assertSameUser(req.user?.id, undefined);

			const parsed = QuerySchema.safeParse(req.query);
			if (!parsed.success) {
				return res
					.status(HttpStatusCodes.BAD_REQUEST)
					.json({ error: "Invalid query", details: parsed.error });
			}
			const q = parsed.data;

			// Resolve the window: explicit bounds, else the last DEFAULT_WINDOW_DAYS.
			const rangeEnd = q.end ? new Date(q.end) : new Date();
			const rangeStart = q.start
				? new Date(q.start)
				: new Date(rangeEnd.getTime() - DEFAULT_WINDOW_DAYS * 86_400_000);

			// If a prescriptionId is supplied, confirm it belongs to the session user
			// before scoping to it (IDOR guard).
			if (q.prescriptionId) {
				const rx = await prisma.prescription.findUnique({
					where: { id: q.prescriptionId },
					select: { userId: true },
				});
				assertResourceOwner(req.user?.id, rx?.userId);
			}

			// Pull the user's doses in the window (always scoped to userId, never a
			// client id). Filter by prescription when requested.
			const doseRows = (await prisma.dose.findMany({
				where: {
					userId,
					...(q.prescriptionId ? { prescriptionId: q.prescriptionId } : {}),
					scheduledFor: { gte: rangeStart, lte: rangeEnd },
				},
				select: { scheduledFor: true, takenAt: true },
				orderBy: { scheduledFor: "asc" },
			})) as Array<{ scheduledFor: Date; takenAt: Date | null }>;

			const events: DoseEvent[] = doseRows.map((d) => ({
				scheduledFor: d.scheduledFor,
				takenAt: d.takenAt,
				// GTM-520 SEAM: no per-dose confidence persisted yet -> defaults to 1.0.
			}));

			// Inventory for MPR: sum the parsed qty across the user's medicines and
			// derive the daily rate from the dose schedule (matching RefillService).
			const prescriptions = (await prisma.prescription.findMany({
				where: {
					userId,
					...(q.prescriptionId ? { id: q.prescriptionId } : {}),
				},
				select: {
					medicines: { select: { qty: true } },
					doses: { select: { scheduledFor: true } },
				},
			})) as Array<{
				medicines: Array<{ qty: string | null }>;
				doses: Array<{ scheduledFor: Date }>;
			}>;

			let initialQty: number | null = null;
			const scheduleDates: Date[] = [];
			for (const rx of prescriptions) {
				for (const m of rx.medicines) {
					const parsedQty = parseQty(m.qty);
					if (parsedQty != null) initialQty = (initialQty ?? 0) + parsedQty;
				}
				for (const dose of rx.doses) scheduleDates.push(dose.scheduledFor);
			}
			const inventory: InventoryInput = {
				initialQty,
				dailyRate: dailyRateFromSchedule(scheduleDates),
			};

			const metrics: AdherenceMetrics = computeAdherenceMetrics(
				events,
				inventory,
				{
					rangeStart,
					rangeEnd,
					onTimeWindowMinutes: q.onTimeWindowMinutes,
				},
			);

			audit(req, "READ", "AdherenceMetrics", q.prescriptionId ?? null, {
				doseCount: events.length,
				totalDays: metrics.window.totalDays,
			});

			return res.status(HttpStatusCodes.OK).json({ metrics });
		} catch (error: unknown) {
			if (error instanceof RouteError) {
				return res.status(error.status).json({ error: error.message });
			}
			console.error("Error in getAdherence:", error);
			const message =
				error instanceof Error
					? error.message
					: "Failed to compute adherence metrics";
			return res
				.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
				.json({ error: message });
		}
	},
};

export default MetricsRoutes;
