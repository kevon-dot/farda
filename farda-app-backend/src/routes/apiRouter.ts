import Paths from "@src/common/constants/Paths";
import { isAuthenticated } from "@src/middleware/isAuthenticated";
import { maybeLimiter, ocrRateLimiter } from "@src/middleware/rateLimiters";
import { Router } from "express";
import OcrRoutes from "./OcrRoutes";
import { createPrescription } from "./PrescriptionRoutes";
import RefillRoutes from "./RefillRoutes";
import ReminderRoutes from "./ReminderRoutes";

/******************************************************************************
                                Setup
******************************************************************************/

const apiRouter = Router();

// ----------------------- Auth routes (better-auth) ---------------------- //
// PUBLIC auth routes (phone/OTP + session management) are now owned entirely by
// better-auth, mounted as `toNodeHandler(auth)` on `/api/auth/*` in server.ts
// (#7/#8/#9). better-auth is the single session/identity system, so the former
// custom `/api/auth/send-otp|verify-otp|social-login` wrapper routes — a
// parallel layer that re-implemented what better-auth already exposes — have
// been removed to avoid two competing auth surfaces. The phone/OTP flow runs
// through better-auth's native phoneNumber plugin endpoints.
//
// Everything below is deny-by-default: each router applies `isAuthenticated`
// (which validates the session via `auth.api.getSession`) so no route is
// reachable without a valid better-auth session.

// NOTE (#35): the express-generator numeric-id User scaffold (UserRoutes /
// UserService / UserRepo / User.model) was incompatible with the cuid Prisma
// `User` model and has been removed. User records are managed by better-auth.
//
// NOTE (#14/#30): the device-user and caregiver routers were thin proxies to
// the dead FARDA_API_URL backend (via the removed DeviceTrackingService). The
// app now calls the Vial API directly, so the proxy layer has been removed.

// ----------------------- Add PrescriptionRouter ------------------------- //

const prescriptionRouter = Router();

// Deny-by-default: every prescription / OCR route (all PHI) requires a valid
// session. Mounted at the TOP so later middleware (rate-limiting, OCR
// validation) can be added alongside per-route.
prescriptionRouter.use(isAuthenticated);

prescriptionRouter.post(Paths.Prescription.Create, createPrescription);
// prescriptionRouter.get(Paths.Prescription.GetAll, PrescriptionRoutes.getAll);
// prescriptionRouter.put(
// 	Paths.Prescription.SetupVial,
// 	PrescriptionRoutes.setupVial,
// );
// prescriptionRouter.delete(
// 	Paths.Prescription.RemoveVial,
// 	PrescriptionRoutes.removeVial,
// );
// prescriptionRouter.delete(Paths.Prescription.Delete, PrescriptionRoutes.delete);

// ----------------------- Add OCR Routes --------------------------------- //
// Rate limiting (issue #10): the OCR extraction endpoints drive GPT-4o calls
// (real cost + abuse surface), so apply a tight limiter (keyed by IP + user
// id) at the mount point. The limiter runs BEFORE multer so abusive callers
// never even upload. Read/save endpoints are not OCR-cost-bearing and are
// already session-gated, so they are left unthrottled here.
const ocrLimiter = maybeLimiter(ocrRateLimiter);

prescriptionRouter.post(
	Paths.Prescription.OcrExtract,
	ocrLimiter,
	...OcrRoutes.extractFromImages,
);
prescriptionRouter.post(
	Paths.Prescription.OcrExtractFromUrls,
	ocrLimiter,
	OcrRoutes.extractFromUrls,
);
prescriptionRouter.post(Paths.Prescription.OcrSave, OcrRoutes.savePrescription);
prescriptionRouter.get(
	Paths.Prescription.OcrGetUser,
	OcrRoutes.getUserPrescriptions,
);
prescriptionRouter.get(
	Paths.Prescription.OcrGetUserDoses,
	OcrRoutes.getUserDoses,
);
prescriptionRouter.post(
	Paths.Prescription.OcrRecordDose,
	OcrRoutes.recordDoseMood,
);

apiRouter.use(prescriptionRouter);

// ----------------------- Add ReminderRouter ----------------------------- //
// Reminder + notification engine (GTM-537). Deny-by-default: every route is
// session-gated. The schedule endpoint feeds local-notification (re)scheduling
// on the device; the events endpoint logs the reminder-response stream that
// triggers the dose-event analytics pipeline.
const reminderRouter = Router();
reminderRouter.use(isAuthenticated);

reminderRouter.get(Paths.Reminders.Schedule, ReminderRoutes.getSchedule);
reminderRouter.post(Paths.Reminders.Events, ReminderRoutes.logEvent);
reminderRouter.put(
	Paths.Reminders.Preferences,
	ReminderRoutes.updatePreferences,
);
reminderRouter.post(
	Paths.Reminders.PushTokens,
	ReminderRoutes.registerPushToken,
);

apiRouter.use(reminderRouter);

// ----------------------- Add RefillRouter ------------------------------- //
// Refill prediction + pharmacy-readiness (GTM-541). Deny-by-default: every
// route is session-gated. GET /refills computes per-prescription depletion +
// refill-due on read (pure RefillService math over existing Rx qty + Dose
// rows); POST /refills/events logs the refill lifecycle; GET /refills/metrics
// surfaces refill-adherence. Pharmacy auto-refill is a STUB seam only.
const refillRouter = Router();
refillRouter.use(isAuthenticated);

refillRouter.get(Paths.Refills.GetAll, RefillRoutes.getRefills);
refillRouter.post(Paths.Refills.Events, RefillRoutes.logEvent);
refillRouter.get(Paths.Refills.Metrics, RefillRoutes.getMetrics);

apiRouter.use(refillRouter);

/******************************************************************************
                                Export
******************************************************************************/

export default apiRouter;
