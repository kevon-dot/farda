import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import {
	assertResourceOwner,
	assertSameUser,
} from "@src/common/utils/authorization";
import { RouteError } from "@src/common/utils/route-errors";
import { logErr } from "@src/common/utils/safeLogger";
import { prisma } from "@src/lib/prisma";
import { type AuditAction, recordAccess } from "@src/services/AuditService";
import {
	computeRefill,
	dailyRateFromSchedule,
	parseQty,
	type RefillPrediction,
} from "@src/services/RefillService";
import type { Request, Response } from "express";
import { z } from "zod";

/******************************************************************************
        Refill prediction + pharmacy-readiness routes (GTM-541)
*******************************************************************************

   * GET  /api/refills          -> per-prescription remaining / days-left /
                                   refill-due, derived on read from inventory
                                   (qty − doses taken) + the daily dose rate.
   * POST /api/refills/events   -> log a refill lifecycle event
                                   (REQUESTED/COMPLETED/DELAYED) keyed to the
                                   session user + prescription.
   * GET  /api/refills/metrics  -> refill-adherence summary (how many refills
                                   were requested on time, completed, delayed).

  Every handler derives the acting user from the validated session (req.user,
  A2 / better-auth) and NEVER trusts a client-supplied userId. The depletion
  math lives in the pure, testable RefillService.

  HARDWARE FLAG: today "remaining" = initial qty − doses taken. When the smart-
  vial weight sensor lands it can feed an authoritative measured remaining count
  into `computeRefill({ measuredRemaining })` without changing these routes.
******************************************************************************/

export const REFILL_EVENT_TYPES = [
	"REQUESTED",
	"COMPLETED",
	"DELAYED",
] as const;

const RefillEventSchema = z.object({
	// The prescription being refilled. Optional so a generic refill note can be
	// logged, but normally always present.
	prescriptionId: z.string().optional(),
	eventType: z.enum(REFILL_EVENT_TYPES),
	// Short, NON-PHI outcome code (e.g. "manual", "auto", "out_of_stock").
	outcome: z.string().max(64).optional(),
	refillDueDate: z.string().datetime().optional(),
	occurredAt: z.string().datetime().optional(),
	channel: z.enum(["MANUAL", "AUTO"]).optional().default("MANUAL"),
	// Non-PHI structured context only. NEVER PHI.
	metadata: z.record(z.string(), z.unknown()).optional(),
});

/**
 * One-line audit helper mirroring ReminderRoutes/OcrRoutes.audit: records
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

const RefillRoutes = {
	/**
	 * GET /api/refills
	 *
	 * Returns the authenticated user's per-prescription refill predictions. For
	 * each prescription we compute, on read:
	 *   - remaining = initial qty (Medicine.qty) − doses taken (Dose.takenAt)
	 *   - dailyRate = derived from the schedule (distinct doses/day)
	 *   - daysLeft, predictedDepletion, refillDue (= depletion − lead time)
	 *
	 * No new persisted state: the calc is pure + reproducible from existing rows.
	 */
	getRefills: async (req: Request, res: Response) => {
		try {
			const userId = assertSameUser(req.user?.id, undefined);

			const prescriptions = await prisma.prescription.findMany({
				where: { userId },
				orderBy: { createdAt: "desc" },
				select: {
					id: true,
					rxNumber: true,
					storeNumber: true,
					pharmacyOrDoctorName: true,
					medicines: {
						select: { medicineName: true, qty: true },
					},
					doses: {
						select: { scheduledFor: true, takenAt: true },
					},
				},
			});

			// Minimal structural shapes for the selected Prisma rows, so the
			// callbacks below are typed even where the generated client types are
			// unavailable (keeps `tsc --noImplicitAny` clean).
			type RxMedicine = { medicineName: string | null; qty: string | null };
			type RxDose = { scheduledFor: Date; takenAt: Date | null };
			type RxRow = {
				id: string;
				rxNumber: string | null;
				storeNumber: string | null;
				pharmacyOrDoctorName: string | null;
				medicines: RxMedicine[];
				doses: RxDose[];
			};

			const now = new Date();
			const refills = (prescriptions as RxRow[]).map((rx: RxRow) => {
				// Initial qty: sum the parsed qty across the Rx's medicines (a
				// prescription may carry multiple medicines, #76). Null when no
				// medicine reported a numeric qty.
				let initialQty: number | null = null;
				for (const m of rx.medicines) {
					const q = parseQty(m.qty);
					if (q != null) initialQty = (initialQty ?? 0) + q;
				}

				const dosesTaken = rx.doses.filter(
					(d: RxDose) => d.takenAt != null,
				).length;
				const dailyRate = dailyRateFromSchedule(
					rx.doses.map((d: RxDose) => d.scheduledFor),
				);

				const prediction: RefillPrediction = computeRefill({
					initialQty,
					dosesTaken,
					dailyRate,
					now,
					// measuredRemaining: <weight-sensor reading> — HARDWARE FLAG,
					// not available yet; falls back to the qty−doses estimate.
				});

				return {
					prescriptionId: rx.id,
					rxNumber: rx.rxNumber,
					storeNumber: rx.storeNumber,
					pharmacyName: rx.pharmacyOrDoctorName,
					medicineName: rx.medicines?.[0]?.medicineName ?? null,
					...prediction,
				};
			});

			audit(req, "READ", "RefillPrediction", null, {
				count: refills.length,
			});

			return res.status(HttpStatusCodes.OK).json({ refills });
		} catch (error: unknown) {
			if (error instanceof RouteError) {
				return res.status(error.status).json({ error: error.message });
			}
			logErr("Error in getRefills", error);
			const message =
				error instanceof Error ? error.message : "Failed to fetch refills";
			return res
				.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
				.json({ error: message });
		}
	},

	/**
	 * POST /api/refills/events
	 *
	 * Logs a single refill lifecycle event (requested/completed/delayed) for the
	 * session user. Field names are kept stable + PHI-free (only ids/types/
	 * timings + a short non-PHI outcome code).
	 */
	logEvent: async (req: Request, res: Response) => {
		try {
			const userId = assertSameUser(req.user?.id, undefined);

			const parsed = RefillEventSchema.safeParse(req.body);
			if (!parsed.success) {
				return res
					.status(HttpStatusCodes.BAD_REQUEST)
					.json({ error: "Invalid request body", details: parsed.error });
			}
			const data = parsed.data;

			// If a prescriptionId is supplied, confirm it belongs to the session
			// user before attaching the event (IDOR guard). A null id is allowed
			// (generic refill note).
			if (data.prescriptionId) {
				const rx = await prisma.prescription.findUnique({
					where: { id: data.prescriptionId },
					select: { userId: true },
				});
				assertResourceOwner(req.user?.id, rx?.userId);
			}

			const event = await prisma.refillEvent.create({
				data: {
					userId,
					prescriptionId: data.prescriptionId ?? null,
					eventType: data.eventType,
					outcome: data.outcome ?? null,
					refillDueDate: data.refillDueDate
						? new Date(data.refillDueDate)
						: null,
					occurredAt: data.occurredAt ? new Date(data.occurredAt) : new Date(),
					channel: data.channel,
					metadata: data.metadata ?? undefined,
				},
			});

			audit(req, "CREATE", "RefillEvent", event.id, {
				eventType: data.eventType,
				channel: data.channel,
			});

			return res.status(HttpStatusCodes.OK).json(event);
		} catch (error: unknown) {
			if (error instanceof RouteError) {
				return res.status(error.status).json({ error: error.message });
			}
			logErr("Error in logEvent", error);
			const message =
				error instanceof Error ? error.message : "Failed to log refill event";
			return res
				.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
				.json({ error: message });
		}
	},

	/**
	 * GET /api/refills/metrics
	 *
	 * Refill-adherence summary for the session user, computed from the
	 * RefillEvent log: counts of requested / completed / delayed events plus a
	 * simple completion rate. PHI-free; surfaced on the refill endpoint so the
	 * app (and any analytics consumer) has a single place to read adherence.
	 */
	getMetrics: async (req: Request, res: Response) => {
		try {
			const userId = assertSameUser(req.user?.id, undefined);

			const grouped = await prisma.refillEvent.groupBy({
				by: ["eventType"],
				where: { userId },
				_count: { _all: true },
			});

			const counts: Record<string, number> = {
				REQUESTED: 0,
				COMPLETED: 0,
				DELAYED: 0,
			};
			for (const row of grouped) {
				counts[row.eventType] = row._count?._all ?? 0;
			}

			// Completion rate = completed / requested (guard divide-by-zero).
			const requested = counts.REQUESTED;
			const completionRate =
				requested > 0
					? Math.round((counts.COMPLETED / requested) * 100) / 100
					: null;

			audit(req, "READ", "RefillMetrics", null, {
				requested,
				completed: counts.COMPLETED,
				delayed: counts.DELAYED,
			});

			return res.status(HttpStatusCodes.OK).json({
				requested: counts.REQUESTED,
				completed: counts.COMPLETED,
				delayed: counts.DELAYED,
				completionRate,
			});
		} catch (error: unknown) {
			if (error instanceof RouteError) {
				return res.status(error.status).json({ error: error.message });
			}
			logErr("Error in getMetrics", error);
			const message =
				error instanceof Error ? error.message : "Failed to fetch metrics";
			return res
				.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
				.json({ error: message });
		}
	},
};

export default RefillRoutes;
