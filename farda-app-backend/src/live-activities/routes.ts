import {
	Router,
	type NextFunction,
	type Request,
	type Response,
} from "express";
import { z } from "zod";
import { isAuthenticated } from "../middleware/isAuthenticated";
import { ConsumerError } from "../reminders/policy";
import { liveActivityDeliveryService } from "./runtime";
import type { LiveActivityDeliveryService } from "./service";

const opaqueId = z.string().regex(/^[A-Za-z0-9._:-]{1,128}$/);
const installationId = z.string().uuid();
const token = z.string().regex(/^[0-9a-f]{64}$/i);
const installationSchema = z.object({ installationId, token }).strict();
const activitySchema = installationSchema
	.extend({ activityId: opaqueId, occurrenceId: opaqueId })
	.strict();

const handle =
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
			else res.status(500).json({ error: "Unable to register this device." });
		}
	};

export function createLiveActivityRouter(
	service: LiveActivityDeliveryService = liveActivityDeliveryService,
) {
	const router = Router();
	router.use(isAuthenticated);
	router.use("/live-activities/tokens", (_req, res, next) => {
		res.setHeader("Cache-Control", "no-store");
		next();
	});
	router.put(
		"/live-activities/tokens/push-to-start",
		handle(async (req, res) => {
			const result = await service.registerInstallation(
				req.user!.id,
				req.user!.sessionId,
				installationSchema.parse(req.body),
			);
			res.json(result);
		}),
	);
	router.put(
		"/live-activities/tokens/activity",
		handle(async (req, res) => {
			res.json(
				await service.registerActivity(
					req.user!.id,
					req.user!.sessionId,
					activitySchema.parse(req.body),
				),
			);
		}),
	);
	router.delete(
		"/live-activities/tokens/:installationId",
		handle(async (req, res) => {
			await service.revokeInstallation(
				req.user!.id,
				installationId.parse(req.params.installationId),
			);
			res.status(204).end();
		}),
	);
	return router;
}
