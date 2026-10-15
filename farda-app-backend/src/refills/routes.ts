import { Router } from "express";
import { z } from "zod";
import { prisma } from "../lib/prisma";
import { isAuthenticated } from "../middleware/isAuthenticated";
import { route } from "../reminders/routes";
import { RefillService } from "./service";

const id = z.string().min(1).max(160),
	key = z.string().min(8).max(160);
const timestamp = z.iso
	.datetime({ offset: true })
	.transform((value) => new Date(value));
export function createRefillRouter(service = new RefillService(prisma)) {
	const router = Router();
	router.use(isAuthenticated);
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
