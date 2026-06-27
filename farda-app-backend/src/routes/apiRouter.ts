import Paths from "@src/common/constants/Paths";
import { isAuthenticated } from "@src/middleware/isAuthenticated";
import { requireAdmin } from "@src/middleware/requireAdmin";
import { Router } from "express";
import CaregiverRoutes from "./CaregiverRoutes";
import DeviceUserRoutes from "./DeviceUserRoutes";
import OcrRoutes from "./OcrRoutes";
import PhoneAuthRoutes from "./PhoneAuthRoutes";
import { createPrescription } from "./PrescriptionRoutes";
import UserRoutes from "./UserRoutes";

/******************************************************************************
                                Setup
******************************************************************************/

const apiRouter = Router();

// ----------------------- Add AuthRouter --------------------------------- //
// PUBLIC routes (OTP / social login). These are intentionally mounted WITHOUT
// the authentication guard since they are used to obtain a session in the
// first place. Everything else below is deny-by-default: each router applies
// `isAuthenticated` at the top so no route is reachable without a valid
// session.

const authRouter = Router();

authRouter.post(Paths.Auth.SendOTP, PhoneAuthRoutes.sendOTP);
authRouter.post(Paths.Auth.VerifyOTP, PhoneAuthRoutes.verifyOTP);
authRouter.post(Paths.Auth.SocialLogin, PhoneAuthRoutes.socialLogin);

apiRouter.use(authRouter);

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

prescriptionRouter.post(
	Paths.Prescription.OcrExtract,
	...OcrRoutes.extractFromImages,
);
prescriptionRouter.post(
	Paths.Prescription.OcrExtractFromUrls,
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
