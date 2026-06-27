import * as fs from "node:fs";
import * as path from "node:path";
import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import {
	assertResourceOwner,
	assertSameUser,
} from "@src/common/utils/authorization";
import { RouteError } from "@src/common/utils/route-errors";
import { prisma } from "@src/lib/prisma";
import {
	extractPrescriptionFromFiles,
	extractPrescriptionFromUrls,
} from "@src/services/OcrService";
import type { Request, Response } from "express";
import multer from "multer";
import { z } from "zod";
import {
	MAX_UPLOAD_BYTES,
	isAllowedImageUpload,
	sniffImageType,
} from "./uploadFilter";

// Configure multer for file uploads. The filter requires BOTH a valid image
// MIME type AND extension (see uploadFilter.ts); content is additionally
// verified by magic bytes after upload, before anything is sent to OCR.
const upload = multer({
	dest: path.join(process.cwd(), "temp_uploads"),
	limits: { fileSize: MAX_UPLOAD_BYTES },
	fileFilter: (_req, file, cb) => {
		if (isAllowedImageUpload(file.mimetype, file.originalname)) {
			cb(null, true);
		} else {
			cb(
				new Error(
					`Invalid file type. Only JPEG, PNG, and WebP allowed. Received: ${file.mimetype} with extension: ${path
						.extname(file.originalname)
						.toLowerCase()}`,
				),
			);
		}
	},
});

// Zod schemas for validation
const MedicineSchema = z.object({
	medicine_name: z.string().optional().default(""),
	generic_name: z.string().optional().default(""),
	instructions: z.string().optional().default(""),
	qty: z.string().optional().default(""),
	refills_info: z.string().optional().default(""),
	side_effects: z.string().optional().default(""),
});

const CreatePrescriptionSchema = z.object({
	// NOTE: any client-supplied userId is intentionally ignored. The acting user
	// is always derived from the authenticated session (see savePrescription).
	userId: z.string().optional(),
	rx_number: z.string().optional().default(""),
	store_number: z.string().optional().default(""),
	pharmacy_or_doctor_name: z.string().optional().default(""),
	contact_details: z.string().optional().default(""),
	date_filled: z.string().optional().default(""),
	date_expired: z.string().optional().default(""),
	address: z.string().optional().default(""),
	deviceId: z.string().nullish(),
	doses_per_day: z
		.number()
		.or(z.string().transform(Number))
		.optional()
		.default(1),
	duration_days: z
		.number()
		.or(z.string().transform(Number))
		.optional()
		.default(30),
	medicines_names: z.array(MedicineSchema).optional().default([]),
});

const RecordMoodSchema = z.object({
	takenAt: z.string().optional(), // ISO date
	mood: z.string().optional(),
	note: z.string().optional(),
});

const ExtractFromUrlSchema = z.object({
	image_urls: z.array(z.string().url()),
});

const OcrRoutes = {
	/**
	 * Extract prescription info from uploaded images using OCR
	 * POST /api/prescriptions/ocr/extract
	 */
	extractFromImages: [
		upload.array("image", 10), // Accept up to 10 image files
		async (req: Request, res: Response) => {
			const tempFilePaths: string[] = [];

			try {
				if (!req.files || !Array.isArray(req.files) || req.files.length === 0) {
					return res
						.status(HttpStatusCodes.BAD_REQUEST)
						.json({ error: "No image files provided" });
				}

				// Collect paths of uploaded files
				for (const file of req.files) {
					tempFilePaths.push((file as Express.Multer.File).path);
				}

				// Defense-in-depth: verify each file's actual content signature
				// (magic bytes) before sending it to the OCR/LLM pipeline. A
				// request can lie about MIME type/extension; this can't.
				for (const filePath of tempFilePaths) {
					const header = fs.readFileSync(filePath).subarray(0, 12);
					if (sniffImageType(header) === null) {
						return res.status(HttpStatusCodes.BAD_REQUEST).json({
							error:
								"Uploaded file is not a valid JPEG, PNG, or WebP image.",
						});
					}
				}

				// Extract prescription data from images
				const extracted = await extractPrescriptionFromFiles(tempFilePaths);

				return res.status(HttpStatusCodes.OK).json(extracted);
			} catch (error: unknown) {
				console.error("Error in extractFromImages:", error);
				const message =
					error instanceof Error
						? error.message
						: "Failed to extract prescription data";
				return res.status(HttpStatusCodes.INTERNAL_SERVER_ERROR).json({
					error: message,
				});
			} finally {
				// Clean up temporary files
				for (const filePath of tempFilePaths) {
					try {
						if (fs.existsSync(filePath)) {
							fs.unlinkSync(filePath);
						}
					} catch (err) {
						console.warn(`Could not delete temp file: ${filePath}`, err);
					}
				}
			}
		},
	],

	/**
	 * Extract prescription info from image URLs using OCR
	 * POST /api/prescriptions/ocr/extract-from-urls
	 */
	extractFromUrls: async (req: Request, res: Response) => {
		try {
			const parsed = ExtractFromUrlSchema.safeParse(req.body);
			if (!parsed.success) {
				return res
					.status(HttpStatusCodes.BAD_REQUEST)
					.json({ error: "Invalid request body", details: parsed.error });
			}

			const extracted = await extractPrescriptionFromUrls(
				parsed.data.image_urls,
			);

			return res.status(HttpStatusCodes.OK).json(extracted);
		} catch (error: unknown) {
			console.error("Error in extractFromUrls:", error);
			const message =
				error instanceof Error
					? error.message
					: "Failed to extract prescription data";
			return res.status(HttpStatusCodes.INTERNAL_SERVER_ERROR).json({
				error: message,
			});
		}
	},

	/**
	 * Save extracted prescription data to database (upsert - one per user)
	 * POST /api/prescriptions/ocr/save
	 */
	savePrescription: async (req: Request, res: Response) => {
		try {
			const parsed = CreatePrescriptionSchema.safeParse(req.body);
			if (!parsed.success) {
				return res
					.status(HttpStatusCodes.BAD_REQUEST)
					.json({ error: "Invalid request body", details: parsed.error });
			}

			const data = parsed.data;

			// IDOR fix: ignore any client-supplied userId and always act as the
			// authenticated session user.
			const userId = assertSameUser(req.user?.id, undefined);

			// Parse date_filled if provided
			let dateFilledObj = null;
			if (data.date_filled) {
				try {
					// Try MM/DD/YYYY format first
					const dateMatch = data.date_filled.match(
						/(\d{1,2})\/(\d{1,2})\/(\d{4})/,
					);
					if (dateMatch) {
						dateFilledObj = new Date(
							parseInt(dateMatch[3], 10),
							parseInt(dateMatch[1], 10) - 1,
							parseInt(dateMatch[2], 10),
						);
					} else {
						// Try YYYY-MM-DD format
						const tempDate = new Date(data.date_filled);
						if (!Number.isNaN(tempDate.getTime())) {
							dateFilledObj = tempDate;
						} else {
							dateFilledObj = null;
						}
					}
				} catch {
					console.warn(`Could not parse date: ${data.date_filled}`);
				}
			}

			// Parse date_expired if provided and valid
			let dateExpiredObj = null;
			if (
				data.date_expired &&
				data.date_expired.toLowerCase() !== "none" &&
				data.date_expired.toLowerCase() !== "n/a"
			) {
				const tempDate = new Date(data.date_expired);
				if (!Number.isNaN(tempDate.getTime())) {
					dateExpiredObj = tempDate;
				}
			}

			// Check if the user actually exists before trying to save
			const userExists = await prisma.user.findUnique({
				where: { id: userId },
			});

			if (!userExists) {
				return res.status(HttpStatusCodes.BAD_REQUEST).json({
					error: `User with ID ${userId} not found. Cannot save prescription.`,
				});
			}

			// Upsert prescription - one per user (replace if exists, create if not)
			const prescription = await prisma.prescription.upsert({
				where: { userId },
				update: {
					medicationName: data.medicines_names[0]?.medicine_name || "",
					dosageInstructions: data.medicines_names[0]?.instructions || "",
					rxNumber: data.rx_number || null,
					storeNumber: data.store_number || null,
					pharmacyOrDoctorName: data.pharmacy_or_doctor_name || null,
					contactDetails: data.contact_details || null,
					dateFilled: dateFilledObj,
					dateExpired: dateExpiredObj,
					address: data.address || null,
					deviceId: data.deviceId || null,
				},
				create: {
					userId,
					medicationName: data.medicines_names[0]?.medicine_name || "",
					dosageInstructions: data.medicines_names[0]?.instructions || "",
					rxNumber: data.rx_number || null,
					storeNumber: data.store_number || null,
					pharmacyOrDoctorName: data.pharmacy_or_doctor_name || null,
					contactDetails: data.contact_details || null,
					dateFilled: dateFilledObj,
					dateExpired: dateExpiredObj,
					address: data.address || null,
					deviceId: data.deviceId || null,
				},
			});

			// Generate Doses for Calendar
			// First, remove any pending future doses so we don't duplicate when upserting
			await prisma.dose.deleteMany({
				where: {
					prescriptionId: prescription.id,
					takenAt: null, // delete only unset future ones
				},
			});

			// Standard schedule (1-4 doses a day)
			const standardTimes = [
				[9], // 1 time: 9am
				[9, 21], // 2 times: 9am, 9pm
				[8, 14, 20], // 3 times: 8am, 2pm, 8pm
				[8, 12, 16, 20], // 4 times
			];
			const dosesCount =
				data.doses_per_day > 0 && data.doses_per_day <= 4
					? data.doses_per_day
					: 1;
			const times = standardTimes[dosesCount - 1];

			const startDate = dateFilledObj || new Date();
			startDate.setHours(0, 0, 0, 0);

			const dosesToInsert = [];
			for (let day = 0; day < data.duration_days; day++) {
				for (const hour of times) {
					const scheduledFor = new Date(startDate);
					scheduledFor.setDate(scheduledFor.getDate() + day);
					scheduledFor.setHours(hour, 0, 0, 0);

					// Only create doses from today onwards ideally, or just create all for history
					dosesToInsert.push({
						userId,
						prescriptionId: prescription.id,
						scheduledFor: scheduledFor,
					});
				}
			}

			if (dosesToInsert.length > 0) {
				await prisma.dose.createMany({
					data: dosesToInsert,
				});
			}

			return res.status(HttpStatusCodes.OK).json(prescription);
		} catch (error: unknown) {
			if (error instanceof RouteError) {
				return res.status(error.status).json({ error: error.message });
			}
			console.error("Error in savePrescription:", error);
			const message =
				error instanceof Error ? error.message : "Failed to save prescription";
			return res.status(HttpStatusCodes.INTERNAL_SERVER_ERROR).json({
				error: message,
			});
		}
	},

	/**
	 * Get prescription for a user (one per user)
	 * GET /api/prescriptions/ocr/user/:userId
	 */
	getUserPrescriptions: async (req: Request, res: Response) => {
		try {
			const { userId: paramUserId } = req.params;

			if (!paramUserId) {
				return res
					.status(HttpStatusCodes.BAD_REQUEST)
					.json({ error: "userId is required" });
			}

			// IDOR fix: reject if the requested userId is not the session user.
			const userId = assertSameUser(req.user?.id, paramUserId as string);

			const prescription = await prisma.prescription.findUnique({
				where: { userId },
			});

			if (!prescription) {
				return res.status(HttpStatusCodes.NOT_FOUND).json({
					error: "No prescription found for this user",
				});
			}

			return res.status(HttpStatusCodes.OK).json(prescription);
		} catch (error: unknown) {
			if (error instanceof RouteError) {
				return res.status(error.status).json({ error: error.message });
			}
			console.error("Error in getUserPrescriptions:", error);
			const message =
				error instanceof Error ? error.message : "Failed to fetch prescription";
			return res.status(HttpStatusCodes.INTERNAL_SERVER_ERROR).json({
				error: message,
			});
		}
	},

	/**
	 * Get doses for user calendar
	 * GET /api/prescriptions/ocr/user/:userId/doses
	 */
	getUserDoses: async (req: Request, res: Response) => {
		try {
			const { userId: paramUserId } = req.params;
			if (!paramUserId) {
				return res
					.status(HttpStatusCodes.BAD_REQUEST)
					.json({ error: "userId is required" });
			}

			// IDOR fix: reject if the requested userId is not the session user.
			const userId = assertSameUser(req.user?.id, paramUserId as string);

			const doses = await prisma.dose.findMany({
				where: { userId },
				orderBy: { scheduledFor: "asc" },
			});

			return res.status(HttpStatusCodes.OK).json(doses);
		} catch (error: unknown) {
			if (error instanceof RouteError) {
				return res.status(error.status).json({ error: error.message });
			}
			console.error("Error in getUserDoses:", error);
			const message =
				error instanceof Error ? error.message : "Failed to fetch doses";
			return res.status(HttpStatusCodes.INTERNAL_SERVER_ERROR).json({
				error: message,
			});
		}
	},

	/**
	 * Record mood and note for a specific dose
	 * POST /api/prescriptions/ocr/doses/:doseId/record
	 */
	recordDoseMood: async (req: Request, res: Response) => {
		try {
			const { doseId } = req.params;
			if (!doseId) {
				return res
					.status(HttpStatusCodes.BAD_REQUEST)
					.json({ error: "doseId is required" });
			}

			const parsed = RecordMoodSchema.safeParse(req.body);
			if (!parsed.success) {
				return res
					.status(HttpStatusCodes.BAD_REQUEST)
					.json({ error: "Invalid request body", details: parsed.error });
			}

			const { mood, note, takenAt } = parsed.data;

			// Ownership check (IDOR fix): load the dose first and confirm it
			// belongs to the authenticated session user before mutating it.
			const existing = await prisma.dose.findUnique({
				where: { id: doseId as string },
				select: { userId: true },
			});
			assertResourceOwner(req.user?.id, existing?.userId);

			const dose = await prisma.dose.update({
				where: { id: doseId as string },
				data: {
					mood: mood || null,
					note: note || null,
					takenAt: takenAt ? new Date(takenAt) : new Date(),
				},
			});

			return res.status(HttpStatusCodes.OK).json(dose);
		} catch (error: unknown) {
			if (error instanceof RouteError) {
				return res.status(error.status).json({ error: error.message });
			}
			console.error("Error in recordDoseMood:", error);
			const message =
				error instanceof Error ? error.message : "Failed to record mood";
			return res.status(HttpStatusCodes.INTERNAL_SERVER_ERROR).json({
				error: message,
			});
		}
	},
};

export default OcrRoutes;
