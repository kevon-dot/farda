import {
	Router,
	type Request,
	type Response,
	type NextFunction,
} from "express";
import { z } from "zod";
import { prisma } from "../lib/prisma";
import { isAuthenticated } from "../middleware/isAuthenticated";
import { ConsumerError, validTimeZone } from "./policy";
import { ReminderService } from "./service";
import {
	inputTwiml,
	makeVoiceAdapter,
	reminderTwiml,
	validWebhook,
	voiceConfig,
} from "./voice";
import { liveActivityDeliveryService } from "../live-activities/runtime";

export const route =
	(handler: (req: Request, res: Response) => Promise<unknown>) =>
	async (req: Request, res: Response, _next: NextFunction) => {
		try {
			await handler(req, res);
		} catch (error) {
			if (error instanceof ConsumerError)
				res.status(error.status).json({ error: error.message });
			else if (error instanceof z.ZodError)
				res
					.status(400)
					.json({ error: "Check the supplied values and try again." });
			else
				res
					.status(500)
					.json({
						error: "Unable to complete this request. Please try again.",
					});
		}
	};
const id = z.string().min(1).max(160);
const clock = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
const preferenceSchema = z
	.object({
		callsEnabled: z.boolean(),
		liveActivitiesEnabled: z.boolean(),
		timeZone: z.string().max(100).refine(validTimeZone),
		quietHoursStart: clock,
		quietHoursEnd: clock,
		callConsent: z.boolean().optional(),
		consentVersion: z.string().max(40).optional(),
	})
	.strict();
export const reminderService = new ReminderService(
	prisma,
	makeVoiceAdapter(),
	voiceConfig(),
	(userId) => liveActivityDeliveryService.readyForUser(userId),
);
export function createReminderRouter(service = reminderService) {
	const router = Router();
	router.use(isAuthenticated);
	router.get(
		"/reminders/preferences",
		route(async (req, res) =>
			res.json(await service.preferences(req.user!.id)),
		),
	);
	router.put(
		"/reminders/preferences",
		route(async (req, res) =>
			res.json(
				await service.savePreferences(
					req.user!.id,
					preferenceSchema.parse(req.body),
				),
			),
		),
	);
	router.get(
		"/reminders/occurrences/:id",
		route(async (req, res) =>
			res.json(await service.occurrence(req.user!.id, id.parse(req.params.id))),
		),
	);
	router.post(
		"/reminders/occurrences/:id/plan",
		route(async (req, res) =>
			res.json(await service.plan(req.user!.id, id.parse(req.params.id))),
		),
	);
	router.post(
		"/reminders/occurrences/:id/snooze",
		route(async (req, res) => {
			const body = z
				.object({
					minutes: z.number().int().min(5).max(30),
					revision: z.number().int().nonnegative().optional(),
				})
				.strict()
				.parse(req.body);
			res.json(
				await service.snooze(
					req.user!.id,
					id.parse(req.params.id),
					body.minutes,
					body.revision,
				),
			);
		}),
	);
	return router;
}
export function createVoiceWebhookRouter(
	service = reminderService,
	config = voiceConfig(),
) {
	const router = Router();
	for (const kind of ["status", "voice", "input"] as const)
		router.post(
			`/reminders/twilio/:id/${kind}`,
			route(async (req, res) => {
				if (
					!req.is("application/x-www-form-urlencoded") ||
					!req.body ||
					Object.values(req.body).some((v) => typeof v !== "string")
				) {
					res.status(403).end();
					return;
				}
				if (
					!validWebhook(
						config,
						req.originalUrl,
						req.get("X-Twilio-Signature"),
						req.body,
					)
				) {
					res.status(403).end();
					return;
				}
				const attemptId = id.parse(req.params.id);
				const result = await service.webhook(attemptId, req.body, kind);
				if (kind === "status") {
					res.status(204).end();
					return;
				}
				res
					.type("text/xml")
					.send(
						kind === "voice"
							? reminderTwiml(
									`${config.publicOrigin}/api/reminders/twilio/${encodeURIComponent(attemptId)}/input`,
									req.body.AnsweredBy,
									result.permitted,
								)
							: inputTwiml(req.body.Digits, result.permitted),
					);
			}),
		);
	return router;
}
