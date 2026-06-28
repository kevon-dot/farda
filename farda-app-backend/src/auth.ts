import env from "@src/common/constants/env";
import { parseCorsOrigins } from "@src/common/utils/http-security";
import { logErr, logInfo } from "@src/common/utils/safeLogger";
import { prisma } from "@src/lib/prisma";
import { betterAuth } from "better-auth";
import { prismaAdapter } from "better-auth/adapters/prisma";
import { bearer, phoneNumber } from "better-auth/plugins";
import { sendSmsOTP, verifyTwilioOTP } from "./services/twilioService";

export const auth = betterAuth({
	// Secret used to sign/encrypt sessions and bearer tokens. Sourced from env
	// only (#8) — never hardcoded. better-auth will throw at startup if this is
	// missing in production, which is the desired fail-closed behavior.
	secret: env.BETTER_AUTH_SECRET,
	// Public base URL better-auth uses to build callback/issuer URLs (#9).
	baseURL: env.BETTER_AUTH_URL,
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
		// Bearer-token sessions for the native/mobile client (#9). The mobile app
		// authenticates with `Authorization: Bearer <token>` instead of cookies;
		// this plugin makes better-auth issue and accept that token.
		bearer(),
		phoneNumber({
			sendOTP: async ({ phoneNumber, code }, _) => {
				// Send OTP via Twilio Verify
				try {
					await sendSmsOTP(phoneNumber, code);
					// PHI-safe: never log the phone number or OTP code in clear text.
					logInfo("OTP sent", { phoneNumber, code });
				} catch (error: any) {
					logErr("Failed to send OTP", { phoneNumber, error });
				}
			},
			// Verify OTP using Twilio Verify service
			verifyOTP: async ({ phoneNumber, code }, _) => {
				try {
					const result = await verifyTwilioOTP(phoneNumber, code);
					return result.status === "approved";
				} catch (error: any) {
					// PHI-safe: never log the phone number or OTP code in clear text.
					logErr("Failed to verify OTP", { phoneNumber, error });
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
