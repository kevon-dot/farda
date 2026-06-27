import env from "@src/common/constants/env";
import twilio from "twilio";

const client = twilio(env.TWILIO_ACCOUNT_SID, env.TWILIO_AUTH_TOKEN);

let verifyClient: any;

function getVerifyClient() {
	if (!verifyClient) {
		const serviceSid = env.TWILIO_VERIFY_SERVICE_SID;
		if (!serviceSid) {
			throw new Error(
				"TWILIO_VERIFY_SERVICE_SID is not set in environment variables",
			);
		}
		verifyClient = client.verify.v2.services(serviceSid);
	}
	return verifyClient;
}

export async function sendSmsOTP(phone: string, code: string) {
	// Use Twilio Verify API for better international support
	// Note: Twilio Verify generates its own codes by default
	// The 'code' parameter is ignored to comply with service settings
	const verify = getVerifyClient();
	return verify.verifications.create({
		to: phone,
		channel: "sms",
	});
}

export async function verifyTwilioOTP(phone: string, code: string) {
	// Verify the OTP code with Twilio Verify service
	const verify = getVerifyClient();
	return verify.verificationChecks.create({
		to: phone,
		code: code,
	});
}
