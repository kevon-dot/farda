import { auth } from "@src/auth";
import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import { z } from "zod";

import type { Req, Res } from "./common/express-types";
import parseReq from "./common/parseReq";

/******************************************************************************
                                Constants
******************************************************************************/

const reqValidators = {
	sendOTP: parseReq(
		z.object({
			phoneNumber: z.string().min(1),
		}),
	),
	verifyOTP: parseReq(
		z.object({
			phoneNumber: z.string().min(1),
			code: z.string().min(1),
		}),
	),
	socialLogin: parseReq(
		z.object({
			provider: z.enum(["google", "apple", "facebook"]),
			idToken: z.string().min(1),
		}),
	),
} as const;

/******************************************************************************
                                Functions
******************************************************************************/

/**
 * Sign in with phone number and password.
 *
 * @route POST /api/auth/sign-in-phone
 */
async function signIn(req: Req, res: Res) {
	try {
		const validated = z
			.object({
				phoneNumber: z.string().min(1),
				password: z.string().min(1),
				rememberMe: z.boolean().optional(),
			})
			.parse(req.body);

		const { phoneNumber, password, rememberMe } = validated;

		const response = await auth.api.signInPhoneNumber({
			body: { phoneNumber, password, rememberMe },
		});

		res.status(HttpStatusCodes.OK).json(response);
	} catch (error: any) {
		console.error("Sign in error:", error);
		res.status(HttpStatusCodes.BAD_REQUEST).json({
			error: error.message || "Failed to sign in",
		});
	}
}

/**
 * Send OTP to phone number for mobile signin.
 *
 * @route POST /api/auth/send-otp
 */
async function sendOTP(req: Req, res: Res) {
	try {
		const validated = reqValidators.sendOTP(req.body);
		const { phoneNumber } = validated;

		const response = await auth.api.sendPhoneNumberOTP({
			body: { phoneNumber },
		});

		res.status(HttpStatusCodes.OK).json(response);
	} catch (error: any) {
		console.error("Send OTP error:", error);
		res.status(HttpStatusCodes.BAD_REQUEST).json({
			error: error.message || "Failed to send OTP",
		});
	}
}

/**
 * Verify OTP and handle signup/signin.
 * If user doesn't exist, creates a new account.
 * If user exists, signs in the user.
 *
 * @route POST /api/auth/verify-otp
 */
async function verifyOTP(req: Req, res: Res) {
	try {
		const validated = reqValidators.verifyOTP(req.body);
		const { phoneNumber, code } = validated;

		const response = await auth.api.verifyPhoneNumber({
			body: { phoneNumber, code },
		});

		res.status(HttpStatusCodes.OK).json(response);
	} catch (error: any) {
		console.error("Verify OTP error:", error);
		res.status(HttpStatusCodes.BAD_REQUEST).json({
			error: error.message || "Failed to verify OTP",
		});
	}
}

/**
 * Handle social login via idToken from mobile apps.
 *
 * @route POST /api/auth/social-login
 */
async function socialLogin(req: Req, res: Res) {
	try {
		const validated = reqValidators.socialLogin(req.body);
		const { provider, idToken } = validated;

		const response = await auth.api.signInSocial({
			body: { provider: provider as any, idToken: { token: idToken } as any },
		});

		res.status(HttpStatusCodes.OK).json(response);
	} catch (error: any) {
		console.error("Social login error:", error);
		res.status(HttpStatusCodes.BAD_REQUEST).json({
			error: error.message || "Failed to authenticate with social provider",
		});
	}
}

/******************************************************************************
                                Export default
******************************************************************************/

export default {
	signIn,
	sendOTP,
	verifyOTP,
	socialLogin,
} as const;
