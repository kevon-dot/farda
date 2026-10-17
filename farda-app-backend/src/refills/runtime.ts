import logger from "jet-logger";
import { prisma } from "../lib/prisma";
import { RefillAgentService } from "./agent";
import { photonRefillsProvider } from "./provider";
import { RefillReconciliationService } from "./reconciliation";

export const refillAgentService = new RefillAgentService(
	prisma,
	photonRefillsProvider,
	undefined,
	(event) => logger.info(JSON.stringify({ event: "refill_agent", ...event })),
);

export const refillReconciliationService = new RefillReconciliationService(
	prisma,
	photonRefillsProvider,
	undefined,
	(event) =>
		logger.info(JSON.stringify({ event: "refill_reconciliation", ...event })),
);
