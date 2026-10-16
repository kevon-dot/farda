import { Router } from 'express';
import { isAuthenticated } from '@src/middleware/isAuthenticated';
import { rateLimit } from '@src/middleware/rateLimit';
import Paths from '@src/common/constants/Paths';
import CaregiverRoutes from './CaregiverRoutes';
import DeviceUserRoutes from './DeviceUserRoutes';
import OcrRoutes from './OcrRoutes';
import PhoneAuthRoutes from './PhoneAuthRoutes';
import { archivePrescription, changeSchedule, createPrescription, doseHistory, listDoses, listPrescriptions, recordDose, updatePrescription } from './PrescriptionRoutes';
import { createReminderRouter, createVoiceWebhookRouter } from '../reminders/routes';
import { createRefillRouter } from '../refills/routes';
import { createRefillAssistantRouter } from '../refills/assistant-routes';
import { DeviceTrackingService } from '../services/DeviceTrackingService';
import { createCircleRouter } from '../circle/routes';
import { createBillingRouter } from '../billing/routes';

const apiRouter = Router();
apiRouter.post(Paths.Auth.SendOTP, rateLimit('otp-send', 5), PhoneAuthRoutes.sendOTP);
apiRouter.post(Paths.Auth.VerifyOTP, rateLimit('otp-verify', 10), PhoneAuthRoutes.verifyOTP);
apiRouter.post(Paths.Auth.SocialLogin, rateLimit('social-signin', 10), PhoneAuthRoutes.socialLogin);
// Provider callbacks authenticate their exact public URL and form body with a
// Twilio signature, not a mobile session. Keep this narrow router before bearer
// auth; its three handlers reject unsigned and malformed requests themselves.
apiRouter.use(createVoiceWebhookRouter());
// All subsequent routes derive account identity from the same revocable bearer
// session. The old public sample /users CRUD is intentionally not mounted.
apiRouter.use(isAuthenticated);
apiRouter.use(createBillingRouter());
apiRouter.get('/auth/session', PhoneAuthRoutes.session);
apiRouter.post('/auth/sign-out', PhoneAuthRoutes.signOut);
apiRouter.use(createReminderRouter());
apiRouter.use(createRefillRouter());
apiRouter.use(createRefillAssistantRouter());
apiRouter.use(createCircleRouter());

apiRouter.get('/prescriptions', listPrescriptions);
apiRouter.post('/prescriptions', createPrescription);
apiRouter.patch('/prescriptions/:id', updatePrescription);
apiRouter.delete('/prescriptions/:id', archivePrescription);
apiRouter.post('/prescriptions/:id/schedules', changeSchedule);
apiRouter.get('/doses', listDoses);
apiRouter.patch('/doses/:id', recordDose);
apiRouter.get('/doses/:id/history', doseHistory);
apiRouter.post(Paths.Prescription.OcrExtract, rateLimit('ocr', 5), ...OcrRoutes.extractFromImages);
apiRouter.post(Paths.Prescription.OcrExtractFromUrls, OcrRoutes.extractFromUrls);
apiRouter.post(Paths.Prescription.OcrSave, OcrRoutes.savePrescription);
apiRouter.get(Paths.Prescription.OcrGetUser, OcrRoutes.getUserPrescriptions);
apiRouter.get(Paths.Prescription.OcrGetUserDoses, OcrRoutes.getUserDoses);
apiRouter.post(Paths.Prescription.OcrRecordDose, OcrRoutes.recordDoseMood);

apiRouter.post(Paths.DeviceUser.Claim, DeviceUserRoutes.claim);
apiRouter.get(Paths.DeviceUser.GetDevices, DeviceUserRoutes.getDevices);
apiRouter.delete(Paths.DeviceUser.UnclaimDevice, DeviceUserRoutes.unclaimDevice);
apiRouter.get(Paths.DeviceUser.GetDeviceEvents, DeviceUserRoutes.getDeviceEvents);
apiRouter.delete(Paths.DeviceUser.DeleteDeviceEvents, DeviceUserRoutes.deleteDeviceEvents);
apiRouter.get(Paths.DeviceUser.SearchDeviceEvents, DeviceUserRoutes.searchDeviceEvents);
apiRouter.get(Paths.DeviceUser.GetAllEvents, DeviceUserRoutes.getAllEvents);
apiRouter.post(Paths.Caregiver.Claim, CaregiverRoutes.claimDevice);
apiRouter.post('/caregiver/invitations/:invitationId/accept', async (req, res) => {
  const invitationId = req.params.invitationId;
  if (!invitationId || invitationId.length > 160) return res.status(400).json({ error: 'Invalid invitation', code: 'invalid_input' });
  const result = await DeviceTrackingService.proxyRequest(`/api/caregiver/invitations/${encodeURIComponent(invitationId)}/accept`, 'POST', req.headers.authorization, {});
  return res.status(result.status).json(result.data);
});
apiRouter.delete(Paths.Caregiver.Remove, CaregiverRoutes.removeCaregiver);
apiRouter.get(Paths.Caregiver.GetDevices, CaregiverRoutes.getDevices);
apiRouter.get(Paths.Caregiver.GetDeviceSummary, CaregiverRoutes.getDeviceSummary);
apiRouter.get(Paths.Caregiver.SearchDevice, CaregiverRoutes.searchDevice);
apiRouter.get(Paths.Caregiver.FilterEvents, CaregiverRoutes.filterEvents);
export default apiRouter;
