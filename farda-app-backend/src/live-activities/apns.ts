import { createPrivateKey, sign } from "node:crypto";
import { connect, type ClientHttp2Stream } from "node:http2";
import { z } from "zod";
import { TokenProtector } from "./crypto";

export interface LiveActivityConfig {
	enabled: boolean;
	environment: "development" | "production";
	teamId: string;
	keyId: string;
	topic: string;
	privateKey: string;
	protector: TokenProtector | null;
}

const identifier = /^[A-Z0-9]{10}$/;
const topic = /^[A-Za-z0-9][A-Za-z0-9.-]{2,199}\.push-type\.liveactivity$/;

export function liveActivityConfig(
	env: NodeJS.ProcessEnv = process.env,
): LiveActivityConfig {
	const environment =
		env.FARDA_APNS_ENVIRONMENT === "production" ? "production" : "development";
	const teamId = env.FARDA_APNS_TEAM_ID || "";
	const keyId = env.FARDA_APNS_KEY_ID || "";
	const configuredTopic = env.FARDA_APNS_LIVE_ACTIVITY_TOPIC || "";
	const privateKey = (env.FARDA_APNS_PRIVATE_KEY || "").replace(/\\n/g, "\n");
	const protector = TokenProtector.fromBase64(
		env.FARDA_LIVE_ACTIVITY_ENCRYPTION_KEY,
	);
	let signingKeyValid = false;
	try {
		const key = createPrivateKey(privateKey);
		signingKeyValid =
			key.asymmetricKeyType === "ec" &&
			key.asymmetricKeyDetails?.namedCurve === "prime256v1";
	} catch {
		/* Missing and malformed keys keep the integration disabled. */
	}
	return {
		enabled:
			env.FARDA_LIVE_ACTIVITY_ENABLED === "true" &&
			(env.FARDA_APNS_ENVIRONMENT === "development" ||
				env.FARDA_APNS_ENVIRONMENT === "production") &&
			identifier.test(teamId) &&
			identifier.test(keyId) &&
			topic.test(configuredTopic) &&
			signingKeyValid &&
			protector !== null,
		environment,
		teamId,
		keyId,
		topic: configuredTopic,
		privateKey,
		protector,
	};
}

const payloadSchema = z.object({
	aps: z
		.object({
			timestamp: z.number().int().nonnegative(),
			event: z.enum(["start", "update", "end"]),
			"content-state": z.record(z.string(), z.unknown()),
			"stale-date": z.number().int().nonnegative().optional(),
			"dismissal-date": z.number().int().nonnegative().optional(),
			"attributes-type": z.literal("FardaRoutineAttributes").optional(),
			"input-push-token": z.literal(1).optional(),
			attributes: z
				.object({ occurrenceId: z.string().min(1).max(128) })
				.strict()
				.optional(),
			alert: z
				.object({ title: z.string().max(80), body: z.string().max(160) })
				.strict()
				.optional(),
		})
		.strict(),
});

export type LiveActivityPayload = z.infer<typeof payloadSchema>;
export function validateLiveActivityPayload(
	payload: unknown,
): LiveActivityPayload {
	return payloadSchema.parse(payload);
}
export interface ApnsResult {
	accepted: boolean;
	status: number;
	reason?: string;
	invalidateToken: boolean;
}
export interface ApnsAdapter {
	enabled: boolean;
	send(
		token: string,
		payload: LiveActivityPayload,
		expiresAt: Date,
	): Promise<ApnsResult>;
}

export class ApnsTransportError extends Error {
	constructor() {
		super("apns_transport_result_unknown");
	}
}

export class ApnsLocalError extends Error {}

export function makeApnsAdapter(
	config: LiveActivityConfig = liveActivityConfig(),
): ApnsAdapter {
	let cachedJwt: { value: string; createdAt: number } | undefined;
	const jwt = () => {
		const now = Math.floor(Date.now() / 1000);
		if (cachedJwt && now - cachedJwt.createdAt < 50 * 60)
			return cachedJwt.value;
		const header = Buffer.from(
			JSON.stringify({ alg: "ES256", kid: config.keyId }),
		).toString("base64url");
		const claims = Buffer.from(
			JSON.stringify({ iss: config.teamId, iat: now }),
		).toString("base64url");
		const unsigned = `${header}.${claims}`;
		const signature = sign("sha256", Buffer.from(unsigned), {
			key: config.privateKey,
			dsaEncoding: "ieee-p1363",
		}).toString("base64url");
		cachedJwt = { value: `${unsigned}.${signature}`, createdAt: now };
		return cachedJwt.value;
	};
	return {
		enabled: config.enabled,
		async send(token, payload, expiresAt) {
			if (!config.enabled) throw new ApnsLocalError("apns_unavailable");
			if (!/^[0-9a-f]{64}$/i.test(token))
				throw new ApnsLocalError("apns_token_invalid");
			const body = JSON.stringify(validateLiveActivityPayload(payload));
			if (Buffer.byteLength(body) > 4096)
				throw new ApnsLocalError("apns_payload_too_large");
			const origin =
				config.environment === "production"
					? "https://api.push.apple.com"
					: "https://api.sandbox.push.apple.com";
			let authorization: string;
			try {
				authorization = `bearer ${jwt()}`;
			} catch {
				throw new ApnsLocalError("apns_signing_failed");
			}
			return new Promise<ApnsResult>((resolve, reject) => {
				let client: ReturnType<typeof connect>;
				try {
					client = connect(origin);
				} catch {
					reject(new ApnsTransportError());
					return;
				}
				let settled = false;
				const finish = (error?: Error, result?: ApnsResult) => {
					if (settled) return;
					settled = true;
					client.close();
					if (error) reject(error);
					else resolve(result!);
				};
				client.setTimeout(10_000, () => finish(new ApnsTransportError()));
				client.once("error", () => finish(new ApnsTransportError()));
				let request: ClientHttp2Stream;
				try {
					request = client.request({
						":method": "POST",
						":path": `/3/device/${token}`,
						authorization,
						"apns-push-type": "liveactivity",
						"apns-topic": config.topic,
						"apns-priority": "10",
						"apns-expiration": String(Math.floor(expiresAt.getTime() / 1000)),
					});
				} catch {
					finish(new ApnsTransportError());
					return;
				}
				let status = 0;
				let response = "";
				request.setEncoding("utf8");
				request.on("response", (headers) => {
					status = Number(headers[":status"] || 0);
				});
				request.on("data", (chunk: string) => {
					if (response.length < 1024) response += chunk;
				});
				request.once("error", () => finish(new ApnsTransportError()));
				request.on("end", () => {
					let reason: string | undefined;
					try {
						const decoded = JSON.parse(response) as { reason?: unknown };
						if (
							typeof decoded.reason === "string" &&
							decoded.reason.length <= 80
						)
							reason = decoded.reason;
					} catch {
						/* Empty success and malformed error bodies need no details. */
					}
					finish(undefined, {
						accepted: status === 200,
						status,
						reason,
						invalidateToken:
							status === 410 ||
							reason === "BadDeviceToken" ||
							reason === "DeviceTokenNotForTopic",
					});
				});
				request.end(body);
			});
		},
	};
}
