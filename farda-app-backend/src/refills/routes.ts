import { Router } from "express";
import logger from "jet-logger";
import { z } from "zod";
import env from "../common/constants/env";
import { prisma } from "../lib/prisma";
import { isAuthenticated } from "../middleware/isAuthenticated";
import { rateLimit } from "../middleware/rateLimit";
import { route } from "../reminders/routes";
import { RefillAgentService } from "./agent";
import { PharmacyHandoffService } from "./pharmacy-handoff";
import { PhotonRefillsProvider } from "./providers/photon";
import { RefillService } from "./service";

const id = z.string().min(1).max(160),
	key = z.string().min(8).max(160);
const timestamp = z.iso
	.datetime({ offset: true })
	.transform((value) => new Date(value));
export function createRefillRouter(
	service = new RefillService(prisma),
	agent = new RefillAgentService(
		prisma,
		new PhotonRefillsProvider({
			enabled: env.FARDA_REFILL_PROVIDER_ENABLED,
			environment: env.FARDA_REFILL_PROVIDER_ENVIRONMENT,
			clientId: env.PHOTON_CLIENT_ID,
			clientSecret: env.PHOTON_CLIENT_SECRET,
		}),
		undefined,
		(event) => logger.info(JSON.stringify({ event: "refill_agent", ...event })),
	),
	handoff = new PharmacyHandoffService(prisma),
) {
	const router = Router();
	router.use(isAuthenticated);
	router.get(
		"/pharmacies/directory",
		route(async (req, res) => {
			const query = z
				.string()
				.trim()
				.min(1)
				.max(100)
				.optional()
				.parse(req.query.query);
			res.json(handoff.directory(query));
		}),
	);
	router.post(
		"/prescriptions/:prescriptionId/pharmacy-handoff",
		rateLimit("pharmacy-handoff", 30, 300),
		route(async (req, res) => {
			const input = z
				.object({
					pharmacyId: z.string().min(1).max(80),
					purpose: z.enum(["refill", "renewal", "transfer", "new_rx"]),
				})
				.strict()
				.parse(req.body);
			res.setHeader("Cache-Control", "no-store");
			res.json(
				await handoff.handoff(
					req.user!.id,
					id.parse(req.params.prescriptionId),
					input.pharmacyId,
					input.purpose,
				),
			);
		}),
	);
	router.use("/refills/agent", (_req, res, next) => {
		res.setHeader("Cache-Control", "no-store");
		next();
	});
	router.get(
		"/refills/agent/:prescriptionId",
		rateLimit("refill-review", 30, 300),
		route(async (req, res) => {
			res.json(
				await agent.review(req.user!.id, id.parse(req.params.prescriptionId)),
			);
		}),
	);
	router.post(
		"/refills/agent/:prescriptionId/submit",
		rateLimit("refill-submit", 10, 300),
		route(async (req, res) => {
			const input = z
				.object({
					reviewToken: z.string().uuid(),
					confirmed: z.literal(true),
					idempotencyKey: key,
				})
				.strict()
				.parse(req.body);
			res.json(
				await agent.submit(
					req.user!.id,
					id.parse(req.params.prescriptionId),
					input,
				),
			);
		}),
	);
	router.post(
		"/refills/agent/:prescriptionId/refresh",
		rateLimit("refill-refresh", 30, 300),
		route(async (req, res) => {
			z.object({})
				.strict()
				.parse(req.body ?? {});
			res.json(
				await agent.refresh(req.user!.id, id.parse(req.params.prescriptionId)),
			);
		}),
	);
	router.get(
		"/refills",
		route(async (req, res) => res.json(await service.list(req.user!.id))),
	);
	router.post(
		"/refills",
		route(async (req, res) => {
			const input = z
				.object({
					prescriptionId: id,
					kind: z
						.enum(["refill", "renewal", "transfer", "new"])
						.default("refill"),
					plannedFor: timestamp.optional(),
				})
				.strict()
				.parse(req.body);
			res.status(201).json(await service.create(req.user!.id, input));
		}),
	);
	router.put(
		"/refills/:id/status",
		route(async (req, res) => {
			const input = z
				.object({
					status: z.enum(["contacted", "ready", "received", "cancelled"]),
				})
				.strict()
				.parse(req.body);
			res.json(
				await service.status(
					req.user!.id,
					id.parse(req.params.id),
					input.status,
				),
			);
		}),
	);
	router.get(
		"/inventory/:prescriptionId",
		route(async (req, res) =>
			res.json(
				await service.inventory(
					req.user!.id,
					id.parse(req.params.prescriptionId),
				),
			),
		),
	);
	router.put(
		"/inventory/:prescriptionId",
		route(async (req, res) => {
			const input = z
				.object({
					quantity: z.number().int().min(0).max(100000),
					observedAt: timestamp.refine(
						(value) =>
							value.getTime() <= Date.now() + 5 * 60_000 &&
							value.getTime() >= Date.now() - 90 * 24 * 60 * 60_000,
					),
					revision: z.number().int().positive().optional(),
					idempotencyKey: key,
				})
				.strict()
				.parse(req.body);
			res.json(
				await service.count(
					req.user!.id,
					id.parse(req.params.prescriptionId),
					input,
				),
			);
		}),
	);
	router.post(
		"/refills/:id/receipt",
		route(async (req, res) => {
			const input = z
				.object({
					quantity: z.number().int().positive().max(100000),
					inventoryRevision: z.number().int().positive(),
					alreadyIncluded: z.boolean(),
					idempotencyKey: key,
				})
				.strict()
				.parse(req.body);
			res.json(
				await service.receipt(req.user!.id, id.parse(req.params.id), input),
			);
		}),
	);
	return router;
}
