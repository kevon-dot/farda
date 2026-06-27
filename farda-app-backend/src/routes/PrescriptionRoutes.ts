import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import { prisma } from "@src/lib/prisma";
import { DeviceTrackingService } from "@src/services/DeviceTrackingService";
import type { Request as IReq, Response as IRes } from "express";

function extractToken(req: IReq): string | undefined {
	return req.headers.authorization;
}

export const createPrescription = async (req: IReq, res: IRes) => {
	try {
		const userId = req.user?.id;
		const { medicationName, dosageInstructions, deviceId } = req.body;

		if (!userId) {
			return res
				.status(HttpStatusCodes.BAD_REQUEST)
				.json({ error: "Missing userId" });
		}

		if (!medicationName) {
			return res
				.status(HttpStatusCodes.BAD_REQUEST)
				.json({ error: "Missing medicationName" });
		}

		// If deviceId is provided, claim it in external API
		if (deviceId) {
			const claimResult = await DeviceTrackingService.proxyRequest(
				"/api/user/claim",
				"POST",
				extractToken(req),
				{ device_id: deviceId },
			);

			if (
				claimResult.status >= 400 &&
				claimResult.status !== 409 // already claimed
			) {
				return res.status(claimResult.status).json({
					error: "Failed to claim device",
					details: claimResult.data,
				});
			}
		}

		const prescription = await prisma.prescription.upsert({
			where: { userId },
			update: {
				medicationName,
				dosageInstructions,
				deviceId: deviceId || null,
			},
			create: {
				userId,
				medicationName,
				dosageInstructions,
				deviceId: deviceId || null,
			},
		});

		return res.status(HttpStatusCodes.OK).json({
			message: "Prescription saved successfully",
			data: prescription,
		});
	} catch (error: any) {
		return res
			.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
			.json({ error: error.message });
	}
};
