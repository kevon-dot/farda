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
	GOOGLE_CLIENT_ID?: string;
	GOOGLE_CLIENT_SECRET?: string;
	APPLE_CLIENT_ID?: string;
	APPLE_CLIENT_SECRET?: string;
	FACEBOOK_CLIENT_ID?: string;
	FACEBOOK_CLIENT_SECRET?: string;
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

const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
const APPLE_CLIENT_ID = process.env.APPLE_CLIENT_ID;
const APPLE_CLIENT_SECRET = process.env.APPLE_CLIENT_SECRET;
const FACEBOOK_CLIENT_ID = process.env.FACEBOOK_CLIENT_ID;
const FACEBOOK_CLIENT_SECRET = process.env.FACEBOOK_CLIENT_SECRET;

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
	GOOGLE_CLIENT_ID,
	GOOGLE_CLIENT_SECRET,
	APPLE_CLIENT_ID,
	APPLE_CLIENT_SECRET,
	FACEBOOK_CLIENT_ID,
	FACEBOOK_CLIENT_SECRET,
};

export default env;
