import Paths from "@src/common/constants/Paths";
import { isAuthenticated } from "@src/middleware/isAuthenticated";
import { maybeLimiter, ocrRateLimiter } from "@src/middleware/rateLimiters";
import { requireAdmin } from "@src/middleware/requireAdmin";
import { Router } from "express";
import CaregiverRoutes from "./CaregiverRoutes";
import DeviceUserRoutes from "./DeviceUserRoutes";
import OcrRoutes from "./OcrRoutes";
import { createPrescription } from "./PrescriptionRoutes";
import UserRoutes from "./UserRoutes";

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

// ----------------------- Add UserRouter --------------------------------- //

const userRouter = Router();

// Deny-by-default: require a valid session for every user route.
userRouter.use(isAuthenticated);

// NOTE: GET /users/all previously dumped every user (PII leak / IDOR). It is
// now admin-locked: only an explicit admin allowlist may call it.
userRouter.get(Paths.Users.Get, requireAdmin, UserRoutes.getAll);
userRouter.post(Paths.Users.Add, UserRoutes.add);
userRouter.put(Paths.Users.Update, UserRoutes.update);
userRouter.delete(Paths.Users.Delete, UserRoutes.delete);

apiRouter.use(userRouter);

// ----------------------- Add DeviceUserRouter --------------------------- //

const deviceUserRouter = Router();

// Deny-by-default: require a valid session for every device-user route.
deviceUserRouter.use(isAuthenticated);

deviceUserRouter.post(Paths.DeviceUser.Claim, DeviceUserRoutes.claim);
deviceUserRouter.get(Paths.DeviceUser.GetDevices, DeviceUserRoutes.getDevices);
deviceUserRouter.delete(
	Paths.DeviceUser.UnclaimDevice,
	DeviceUserRoutes.unclaimDevice,
);
deviceUserRouter.get(
	Paths.DeviceUser.GetDeviceEvents,
	DeviceUserRoutes.getDeviceEvents,
);
deviceUserRouter.delete(
	Paths.DeviceUser.DeleteDeviceEvents,
	DeviceUserRoutes.deleteDeviceEvents,
);
deviceUserRouter.get(
	Paths.DeviceUser.SearchDeviceEvents,
	DeviceUserRoutes.searchDeviceEvents,
);
deviceUserRouter.get(
	Paths.DeviceUser.GetAllEvents,
	DeviceUserRoutes.getAllEvents,
);

apiRouter.use(deviceUserRouter);

// ----------------------- Add CaregiverRouter ---------------------------- //

const caregiverRouter = Router();

// Deny-by-default: require a valid session for every caregiver route.
caregiverRouter.use(isAuthenticated);

caregiverRouter.post(Paths.Caregiver.Claim, CaregiverRoutes.claimDevice);
caregiverRouter.delete(Paths.Caregiver.Remove, CaregiverRoutes.removeCaregiver);
caregiverRouter.get(Paths.Caregiver.GetDevices, CaregiverRoutes.getDevices);
caregiverRouter.get(
	Paths.Caregiver.GetDeviceSummary,
	CaregiverRoutes.getDeviceSummary,
);
caregiverRouter.get(Paths.Caregiver.SearchDevice, CaregiverRoutes.searchDevice);
caregiverRouter.get(Paths.Caregiver.FilterEvents, CaregiverRoutes.filterEvents);

apiRouter.use(caregiverRouter);

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

/******************************************************************************
                                Export
******************************************************************************/

export default apiRouter;
