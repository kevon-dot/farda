import env from "@src/common/constants/env";
import { parseCorsOrigins } from "@src/common/utils/http-security";
import { prisma } from "@src/lib/prisma";
import { betterAuth } from "better-auth";
import { prismaAdapter } from "better-auth/adapters/prisma";
import { phoneNumber } from "better-auth/plugins";
import { sendSmsOTP, verifyTwilioOTP } from "./services/twilioService";

export const auth = betterAuth({
	// Align trusted origins with the CORS allowlist (#31) so better-auth accepts
	// requests from the same set of explicitly allowed origins.
	trustedOrigins: parseCorsOrigins(env.CORS_ORIGINS),
	database: prismaAdapter(prisma, {
		provider: "postgresql",
	}),
	socialProviders: {
		google: {
			clientId: env.GOOGLE_CLIENT_ID as string,
			clientSecret: env.GOOGLE_CLIENT_SECRET as string,
		},
		apple: {
			clientId: env.APPLE_CLIENT_ID as string,
			clientSecret: env.APPLE_CLIENT_SECRET as string,
		},
		facebook: {
			clientId: env.FACEBOOK_CLIENT_ID as string,
			clientSecret: env.FACEBOOK_CLIENT_SECRET as string,
		},
	},
	plugins: [
		phoneNumber({
			sendOTP: async ({ phoneNumber, code }, _) => {
				// Send OTP via Twilio Verify
				try {
					await sendSmsOTP(phoneNumber, code);
					console.log(`OTP sent to ${phoneNumber}`);
				} catch (error: any) {
					console.error(
						`Failed to send OTP to ${phoneNumber}:`,
						error.message || error,
					);
					console.error("Error details:", error);
				}
			},
			// Verify OTP using Twilio Verify service
			verifyOTP: async ({ phoneNumber, code }, _) => {
				try {
					const result = await verifyTwilioOTP(phoneNumber, code);
					return result.status === "approved";
				} catch (error: any) {
					console.error(
						`Failed to verify OTP for ${phoneNumber}:`,
						error.message || error,
					);
					return false;
				}
			},
			// Phone number is primary login - no email required
			signUpOnVerification: {
				getTempEmail: (phoneNumber: any) => `${phoneNumber}@phone-only.local`,
				getTempName: (phoneNumber: any) => phoneNumber,
			},
		}),
	],
});
