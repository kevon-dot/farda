import Paths from "@src/common/constants/Paths";
import { isAuthenticated } from "@src/middleware/isAuthenticated";
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

// ----------------------- Add UserRouter --------------------------------- //

const userRouter = Router();

userRouter.get(Paths.Users.Get, UserRoutes.getAll);
userRouter.post(Paths.Users.Add, UserRoutes.add);
userRouter.put(Paths.Users.Update, UserRoutes.update);
userRouter.delete(Paths.Users.Delete, UserRoutes.delete);

apiRouter.use(userRouter);

// ----------------------- Add AuthRouter --------------------------------- //

const authRouter = Router();

authRouter.post(Paths.Auth.SendOTP, PhoneAuthRoutes.sendOTP);
authRouter.post(Paths.Auth.VerifyOTP, PhoneAuthRoutes.verifyOTP);
authRouter.post(Paths.Auth.SocialLogin, PhoneAuthRoutes.socialLogin);

apiRouter.use(authRouter);

// ----------------------- Add DeviceUserRouter --------------------------- //

const deviceUserRouter = Router();

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

prescriptionRouter.post(
	Paths.Prescription.Create,
	isAuthenticated,
	createPrescription,
);
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
