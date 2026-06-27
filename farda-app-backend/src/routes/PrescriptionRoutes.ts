import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import { prisma } from "@src/lib/prisma";
import type { Request as IReq, Response as IRes } from "express";

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

		// NOTE (#14/#30): device claiming previously proxied to FARDA_API_URL via
		// the now-removed DeviceTrackingService. The app calls the Vial API
		// directly, so we no longer claim the device here; the deviceId is simply
		// persisted on the prescription.

		// Create a new prescription (a user may have many) with the supplied
		// medication as its first Medicine row.
		const prescription = await prisma.prescription.create({
			data: {
				userId,
				deviceId: deviceId || null,
				medicines: {
					create: [
						{
							medicineName: medicationName,
							dosageInstructions: dosageInstructions || null,
						},
					],
				},
			},
			include: { medicines: true },
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
