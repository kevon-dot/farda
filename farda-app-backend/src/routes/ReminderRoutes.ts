import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import {
	assertResourceOwner,
	assertSameUser,
} from "@src/common/utils/authorization";
import { RouteError } from "@src/common/utils/route-errors";
import { logErr } from "@src/common/utils/safeLogger";
import { prisma } from "@src/lib/prisma";
import { type AuditAction, recordAccess } from "@src/services/AuditService";
import type { Request, Response } from "express";
import { z } from "zod";

/******************************************************************************
            Reminder + notification engine routes (GTM-537)
*******************************************************************************

  The Main API is the source of truth + response log for the reminder engine:

   * GET  /api/reminders/schedule      -> the user's upcoming reminders (derived
                                          from Dose.scheduledFor + per-Rx config),
                                          so reminders survive reinstall + feed
                                          analytics.
   * POST /api/reminders/events        -> log a single reminder-response event
                                          (DELIVERED/OPENED/SNOOZED/DISMISSED/
                                          ACTIONED) keyed to the session user.
   * PUT  /api/reminders/preferences   -> store delivery prefs (timezone + quiet
                                          hours). The APP enforces timing.
   * POST /api/reminders/push-tokens   -> register an FCM/APNs token (SCAFFOLD;
                                          sending push is the flagged part).

  Every handler derives the acting user from the validated session (req.user,
  A2 / better-auth) and NEVER trusts a client-supplied userId.
******************************************************************************/

/**
 * Allowed reminder-response event types. Kept as a stable, explicit set so the
 * analytics pipeline downstream can rely on the vocabulary.
 */
export const REMINDER_EVENT_TYPES = [
	"DELIVERED",
	"OPENED",
	"SNOOZED",
	"DISMISSED",
	"ACTIONED",
] as const;

const ReminderEventSchema = z.object({
	// The dose this reminder is for. Optional so a generic/aggregate reminder can
	// still be logged, but normally always present.
	doseId: z.string().optional(),
	eventType: z.enum(REMINDER_EVENT_TYPES),
	// ISO timestamps from the device.
	scheduledFor: z.string().datetime().optional(),
	occurredAt: z.string().datetime().optional(),
	snoozeMinutes: z.number().int().nonnegative().optional(),
	timeToActionMs: z.number().int().nonnegative().optional(),
	channel: z.enum(["LOCAL", "PUSH"]).optional().default("LOCAL"),
	// Non-PHI structured context only (platform, appVersion, ...). NEVER PHI.
	metadata: z.record(z.string(), z.unknown()).optional(),
});

const PreferencesSchema = z.object({
	// IANA timezone name, e.g. "America/New_York". Empty/omitted clears it.
	timezone: z.string().optional(),
	// Minutes-from-local-midnight in [0, 1440). null clears the bound.
	quietHoursStart: z.number().int().min(0).max(1439).nullish(),
	quietHoursEnd: z.number().int().min(0).max(1439).nullish(),
});

const PushTokenSchema = z.object({
	token: z.string().min(1),
	platform: z.enum(["fcm", "apns"]),
	deviceId: z.string().optional(),
});

/**
 * One-line audit helper mirroring OcrRoutes.audit: records ids/types/action +
 * request metadata only (never PHI), and never throws / blocks the response.
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

const ReminderRoutes = {
	/**
	 * GET /api/reminders/schedule
	 *
	 * Returns the authenticated user's UPCOMING reminders, derived from their
	 * Dose rows (the source of truth for WHEN) joined with each prescription's
	 * reminder config + the user's delivery preferences. The app uses this to
	 * (re)schedule local notifications on launch / schedule change, so reminders
	 * survive reinstall. Only future, not-yet-taken doses from reminder-enabled
	 * prescriptions are returned.
	 */
	getSchedule: async (req: Request, res: Response) => {
		try {
			const userId = assertSameUser(req.user?.id, undefined);

			// Optional ?limit (default 100, capped) and ?from (ISO) so the client
			// can ask for "the next N upcoming reminders from now".
			const limitRaw = Number(req.query.limit);
			const limit =
				Number.isFinite(limitRaw) && limitRaw > 0
					? Math.min(Math.floor(limitRaw), 500)
					: 100;
			const fromRaw =
				typeof req.query.from === "string" ? new Date(req.query.from) : null;
			const from =
				fromRaw && !Number.isNaN(fromRaw.getTime()) ? fromRaw : new Date();

			const user = await prisma.user.findUnique({
				where: { id: userId },
				select: {
					timezone: true,
					quietHoursStart: true,
					quietHoursEnd: true,
				},
			});

			const doses = await prisma.dose.findMany({
				where: {
					userId,
					takenAt: null,
					scheduledFor: { gte: from },
					prescription: { reminderEnabled: true },
				},
				orderBy: { scheduledFor: "asc" },
				take: limit,
				select: {
					id: true,
					prescriptionId: true,
					scheduledFor: true,
					prescription: {
						select: {
							reminderEnabled: true,
							reminderTimes: true,
							medicines: { select: { medicineName: true }, take: 1 },
						},
					},
				},
			});

			// Shape a thin, client-friendly schedule. We DO include the (single)
			// medicine name here because it is shown in the notification body and
			// the app already holds this PHI; it is NOT written to the audit log.
			const reminders = doses.map((d) => ({
				doseId: d.id,
				prescriptionId: d.prescriptionId,
				scheduledFor: d.scheduledFor,
				reminderTimes: d.prescription?.reminderTimes ?? null,
				medicineName: d.prescription?.medicines?.[0]?.medicineName ?? null,
			}));

			// HIPAA audit: the user's schedule (PHI) was read. Count only.
			audit(req, "READ", "ReminderSchedule", null, {
				count: reminders.length,
			});

			return res.status(HttpStatusCodes.OK).json({
				preferences: {
					timezone: user?.timezone ?? null,
					quietHoursStart: user?.quietHoursStart ?? null,
					quietHoursEnd: user?.quietHoursEnd ?? null,
				},
				reminders,
			});
		} catch (error: unknown) {
			if (error instanceof RouteError) {
				return res.status(error.status).json({ error: error.message });
			}
			logErr("Error in getSchedule", error);
			const message =
				error instanceof Error ? error.message : "Failed to fetch schedule";
			return res
				.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
				.json({ error: message });
		}
	},

	/**
	 * POST /api/reminders/events
	 *
	 * Logs a single reminder-response event (delivered/opened/snoozed/dismissed/
	 * actioned) for the session user. This is the trigger of the dose-event data
	 * pipeline; field names are kept stable + PHI-free (only ids/types/timings).
	 */
	logEvent: async (req: Request, res: Response) => {
		try {
			const userId = assertSameUser(req.user?.id, undefined);

			const parsed = ReminderEventSchema.safeParse(req.body);
			if (!parsed.success) {
				return res
					.status(HttpStatusCodes.BAD_REQUEST)
					.json({ error: "Invalid request body", details: parsed.error });
			}
			const data = parsed.data;

			// If a doseId is supplied, confirm it belongs to the session user
			// before attaching the event (IDOR guard). Unknown/foreign doses are
			// rejected; a null doseId is allowed (generic reminder).
			if (data.doseId) {
				const dose = await prisma.dose.findUnique({
					where: { id: data.doseId },
					select: { userId: true },
				});
				assertResourceOwner(req.user?.id, dose?.userId);
			}

			const event = await prisma.reminderResponseEvent.create({
				data: {
					userId,
					doseId: data.doseId ?? null,
					eventType: data.eventType,
					scheduledFor: data.scheduledFor ? new Date(data.scheduledFor) : null,
					occurredAt: data.occurredAt ? new Date(data.occurredAt) : new Date(),
					snoozeMinutes: data.snoozeMinutes ?? null,
					timeToActionMs: data.timeToActionMs ?? null,
					channel: data.channel,
					metadata: data.metadata ?? undefined,
				},
			});

			// HIPAA audit: a reminder event (structured, non-PHI) was created.
			audit(req, "CREATE", "ReminderResponseEvent", event.id, {
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
				error instanceof Error ? error.message : "Failed to log event";
			return res
				.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
				.json({ error: message });
		}
	},

	/**
	 * PUT /api/reminders/preferences
	 *
	 * Stores the user's delivery preferences (timezone + quiet hours). The app
	 * ENFORCES timing; the backend only persists so prefs survive reinstall and
	 * are available to analytics.
	 */
	updatePreferences: async (req: Request, res: Response) => {
		try {
			const userId = assertSameUser(req.user?.id, undefined);

			const parsed = PreferencesSchema.safeParse(req.body);
			if (!parsed.success) {
				return res
					.status(HttpStatusCodes.BAD_REQUEST)
					.json({ error: "Invalid request body", details: parsed.error });
			}
			const data = parsed.data;

			const user = await prisma.user.update({
				where: { id: userId },
				data: {
					timezone: data.timezone ?? undefined,
					// `null` explicitly clears the bound; `undefined` leaves it.
					quietHoursStart:
						data.quietHoursStart === undefined
							? undefined
							: data.quietHoursStart,
					quietHoursEnd:
						data.quietHoursEnd === undefined ? undefined : data.quietHoursEnd,
				},
				select: {
					timezone: true,
					quietHoursStart: true,
					quietHoursEnd: true,
				},
			});

			audit(req, "UPDATE", "User", userId, { field: "reminderPreferences" });

			return res.status(HttpStatusCodes.OK).json(user);
		} catch (error: unknown) {
			if (error instanceof RouteError) {
				return res.status(error.status).json({ error: error.message });
			}
			logErr("Error in updatePreferences", error);
			const message =
				error instanceof Error ? error.message : "Failed to update preferences";
			return res
				.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
				.json({ error: message });
		}
	},

	/**
	 * POST /api/reminders/push-tokens
	 *
	 * SCAFFOLD: registers an FCM/APNs token for this device so the backend CAN
	 * target push later. Upserts by token (re-registering the same token is
	 * idempotent). SENDING push is NOT implemented here (needs a Firebase
	 * project + APNs cert — flagged for the maintainer).
	 */
	registerPushToken: async (req: Request, res: Response) => {
		try {
			const userId = assertSameUser(req.user?.id, undefined);

			const parsed = PushTokenSchema.safeParse(req.body);
			if (!parsed.success) {
				return res
					.status(HttpStatusCodes.BAD_REQUEST)
					.json({ error: "Invalid request body", details: parsed.error });
			}
			const data = parsed.data;

			// Upsert by the unique token so a device re-registering the same token
			// just refreshes its owner/platform rather than erroring on conflict.
			const pushToken = await prisma.pushToken.upsert({
				where: { token: data.token },
				create: {
					userId,
					token: data.token,
					platform: data.platform,
					deviceId: data.deviceId ?? null,
				},
				update: {
					userId,
					platform: data.platform,
					deviceId: data.deviceId ?? null,
				},
				select: { id: true, platform: true, createdAt: true },
			});

			audit(req, "CREATE", "PushToken", pushToken.id, {
				platform: data.platform,
			});

			return res.status(HttpStatusCodes.OK).json(pushToken);
		} catch (error: unknown) {
			if (error instanceof RouteError) {
				return res.status(error.status).json({ error: error.message });
			}
			logErr("Error in registerPushToken", error);
			const message =
				error instanceof Error ? error.message : "Failed to register token";
			return res
				.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
				.json({ error: message });
		}
	},
};

export default ReminderRoutes;
