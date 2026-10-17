import { prisma } from "../lib/prisma";
import { liveActivityConfig, makeApnsAdapter } from "./apns";
import { LiveActivityDeliveryService } from "./service";

export const liveActivityRuntimeConfig = liveActivityConfig();
export const liveActivityDeliveryService = new LiveActivityDeliveryService(
	prisma,
	makeApnsAdapter(liveActivityRuntimeConfig),
	liveActivityRuntimeConfig,
);
