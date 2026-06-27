import path from "node:path";
import dotenv from "dotenv";

// 1. Determine the file path
// Using path.resolve is safer than strings for cross-platform compatibility
const envFile =
	process.env.NODE_ENV === "production" ? ".env" : ".env.development";

dotenv.config({ path: path.resolve(__dirname, "../../../", envFile) });

// 2. Define types for better IntelliSense
export interface EnvConfig {
	HOST: string;
	PORT: number;
	NODE_ENV: "development" | "production";
	DATABASE_URL?: string;
	FARDA_API_URL?: string;
	TWILIO_ACCOUNT_SID?: string;
	TWILIO_AUTH_TOKEN?: string;
	TWILIO_PHONE_NUMBER?: string;
	TWILIO_VERIFY_SERVICE_SID?: string;
	DISABLE_HELMET?: boolean;
	CORS_ORIGINS?: string;
	OPENAI_API_KEY?: string;
	// better-auth (#7/#8/#9). Secret used to sign/encrypt sessions & tokens —
	// MUST come from env, never hardcoded. BETTER_AUTH_URL is the public base URL
	// better-auth uses to build callback/issuer URLs.
	BETTER_AUTH_SECRET?: string;
	BETTER_AUTH_URL?: string;
	GOOGLE_CLIENT_ID?: string;
	GOOGLE_CLIENT_SECRET?: string;
	APPLE_CLIENT_ID?: string;
	APPLE_CLIENT_SECRET?: string;
	FACEBOOK_CLIENT_ID?: string;
	FACEBOOK_CLIENT_SECRET?: string;
	// Rate limiting (issue #10). All optional; rateLimiters.ts applies safe
	// defaults when unset. Windows are in milliseconds, maxes are request counts.
	RATE_LIMIT_DISABLED?: boolean;
	AUTH_RATE_LIMIT_WINDOW_MS?: number;
	AUTH_RATE_LIMIT_MAX?: number;
	OCR_RATE_LIMIT_WINDOW_MS?: number;
	OCR_RATE_LIMIT_MAX?: number;
}

// 3. Export individual constants
const HOST = process.env.HOST || "127.0.0.1";
const PORT = Number(process.env.PORT) || 8000;

const NODE_ENV =
	process.env.NODE_ENV === "production" ? "production" : "development";

const DATABASE_URL = process.env.DATABASE_URL;
const FARDA_API_URL = process.env.FARDA_API_URL;

const TWILIO_ACCOUNT_SID = process.env.TWILIO_ACCOUNT_SID;
const TWILIO_AUTH_TOKEN = process.env.TWILIO_AUTH_TOKEN;
const TWILIO_PHONE_NUMBER = process.env.TWILIO_PHONE_NUMBER;
const TWILIO_VERIFY_SERVICE_SID = process.env.TWILIO_VERIFY_SERVICE_SID;
// biome-ignore lint/suspicious/noDoubleEquals: <String Boolean>
const DISABLE_HELMET = process.env.DISABLE_HELMET == "true";
const CORS_ORIGINS = process.env.CORS_ORIGINS;
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

// better-auth (#7/#8/#9). Read from env only — never hardcode a secret.
const BETTER_AUTH_SECRET = process.env.BETTER_AUTH_SECRET;
const BETTER_AUTH_URL = process.env.BETTER_AUTH_URL;

const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
const APPLE_CLIENT_ID = process.env.APPLE_CLIENT_ID;
const APPLE_CLIENT_SECRET = process.env.APPLE_CLIENT_SECRET;
const FACEBOOK_CLIENT_ID = process.env.FACEBOOK_CLIENT_ID;
const FACEBOOK_CLIENT_SECRET = process.env.FACEBOOK_CLIENT_SECRET;

// Rate limiting (issue #10). Parsed leniently: a blank/invalid numeric env var
// falls back to `undefined` so rateLimiters.ts can apply its own safe default.
const toOptionalNumber = (value: string | undefined): number | undefined => {
	if (value === undefined || value.trim() === "") {
		return undefined;
	}
	const parsed = Number(value);
	return Number.isFinite(parsed) ? parsed : undefined;
};

// biome-ignore lint/suspicious/noDoubleEquals: <String Boolean>
const RATE_LIMIT_DISABLED = process.env.RATE_LIMIT_DISABLED == "true";
const AUTH_RATE_LIMIT_WINDOW_MS = toOptionalNumber(
	process.env.AUTH_RATE_LIMIT_WINDOW_MS,
);
const AUTH_RATE_LIMIT_MAX = toOptionalNumber(process.env.AUTH_RATE_LIMIT_MAX);
const OCR_RATE_LIMIT_WINDOW_MS = toOptionalNumber(
	process.env.OCR_RATE_LIMIT_WINDOW_MS,
);
const OCR_RATE_LIMIT_MAX = toOptionalNumber(process.env.OCR_RATE_LIMIT_MAX);

// 4. Grouped Export (The "How")
const env: EnvConfig = {
	HOST,
	PORT,
	NODE_ENV,
	DATABASE_URL,
	FARDA_API_URL,
	TWILIO_ACCOUNT_SID,
	TWILIO_AUTH_TOKEN,
	TWILIO_PHONE_NUMBER,
	TWILIO_VERIFY_SERVICE_SID,
	DISABLE_HELMET,
	CORS_ORIGINS,
	OPENAI_API_KEY,
	BETTER_AUTH_SECRET,
	BETTER_AUTH_URL,
	GOOGLE_CLIENT_ID,
	GOOGLE_CLIENT_SECRET,
	APPLE_CLIENT_ID,
	APPLE_CLIENT_SECRET,
	FACEBOOK_CLIENT_ID,
	FACEBOOK_CLIENT_SECRET,
	RATE_LIMIT_DISABLED,
	AUTH_RATE_LIMIT_WINDOW_MS,
	AUTH_RATE_LIMIT_MAX,
	OCR_RATE_LIMIT_WINDOW_MS,
	OCR_RATE_LIMIT_MAX,
};

export default env;
