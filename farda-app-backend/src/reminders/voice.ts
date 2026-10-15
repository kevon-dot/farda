import twilio from "twilio";

export interface VoiceConfig {
	enabled: boolean;
	accountSid: string;
	authToken: string;
	from: string;
	publicOrigin: string;
	allowedPrefixes: string[];
	maxCallsPerHour: number;
}
export function voiceConfig(env: NodeJS.ProcessEnv = process.env): VoiceConfig {
	let publicOrigin = "";
	try {
		const url = new URL(env.FARDA_PUBLIC_BASE_URL || "");
		if (
			url.protocol === "https:" &&
			url.pathname === "/" &&
			!url.search &&
			!url.hash &&
			!url.username &&
			!url.password
		)
			publicOrigin = url.origin;
	} catch {
		/* Disabled until a canonical HTTPS origin is configured. */
	}
	const accountSid = env.TWILIO_ACCOUNT_SID || "",
		authToken = env.TWILIO_AUTH_TOKEN || "",
		from = env.FARDA_TWILIO_VOICE_FROM || "";
	const prefixes = (env.FARDA_VOICE_ALLOWED_PREFIXES || "")
		.split(",")
		.map((s) => s.trim())
		.filter((s) => /^\+[1-9]\d{0,3}$/.test(s));
	const cap = Number(env.FARDA_VOICE_MAX_CALLS_PER_HOUR || 20);
	return {
		enabled:
			env.FARDA_VOICE_ENABLED === "true" &&
			!!accountSid &&
			!!authToken &&
			/^\+[1-9]\d{7,14}$/.test(from) &&
			!!publicOrigin &&
			prefixes.length > 0,
		accountSid,
		authToken,
		from,
		publicOrigin,
		allowedPrefixes: prefixes,
		maxCallsPerHour: Number.isInteger(cap) && cap > 0 ? Math.min(cap, 100) : 20,
	};
}
export interface VoiceAdapter {
	enabled: boolean;
	send(attemptId: string, to: string): Promise<{ providerId: string }>;
	cancel(providerId: string): Promise<void>;
}
export function makeVoiceAdapter(config = voiceConfig()): VoiceAdapter {
	// Never instantiate a provider client, much less call it, in disabled mode.
	const client = config.enabled
		? twilio(config.accountSid, config.authToken, {
				autoRetry: false,
				timeout: 10_000,
			})
		: null;
	return {
		enabled: !!client,
		async send(attemptId, to) {
			if (
				!client ||
				!config.allowedPrefixes.some((prefix) => to.startsWith(prefix))
			)
				throw new Error("voice_unavailable");
			const base = `${config.publicOrigin}/api/reminders/twilio/${encodeURIComponent(attemptId)}`;
			const call = await client.calls.create({
				to,
				from: config.from,
				url: `${base}/voice`,
				method: "POST",
				statusCallback: `${base}/status`,
				statusCallbackMethod: "POST",
				statusCallbackEvent: ["initiated", "ringing", "answered", "completed"],
				machineDetection: "Enable",
				asyncAmd: "false",
				record: false,
				timeout: 25,
				timeLimit: 60,
			});
			return { providerId: call.sid };
		},
		async cancel(providerId) {
			if (client)
				await client.calls(providerId).update({ status: "completed" });
		},
	};
}
export function validWebhook(
	config: VoiceConfig,
	originalUrl: string,
	signature: string | undefined,
	body: Record<string, string>,
) {
	if (
		!config.enabled ||
		!signature ||
		body.AccountSid !== config.accountSid ||
		!originalUrl.startsWith("/api/reminders/twilio/")
	)
		return false;
	return twilio.validateRequest(
		config.authToken,
		signature,
		`${config.publicOrigin}${originalUrl}`,
		body,
	);
}
export function reminderTwiml(
	actionUrl: string,
	answeredBy: string | undefined,
	permitted: boolean,
) {
	const response = new twilio.twiml.VoiceResponse();
	// Synchronous answering-machine detection is an imperfect extra safeguard;
	// unknown/machine/fax receives no spoken reminder. No recording is enabled.
	if (!permitted || answeredBy !== "human") {
		response.hangup();
		return response.toString();
	}
	const gather = response.gather({
		numDigits: 1,
		timeout: 6,
		action: actionUrl,
		method: "POST",
	});
	gather.say(
		"Hi, this is your automated Farda reminder. Your routine is ready when you are. Open Farda to check in. For help opening your private check-in, press 1. To stop reminder calls, press 9.",
	);
	response.hangup();
	return response.toString();
}
export function inputTwiml(digit: string, permitted: boolean) {
	const response = new twilio.twiml.VoiceResponse();
	if (digit === "9") response.say("Reminder calls are now turned off.");
	else if (permitted && digit === "1")
		response.say(
			"Open the Farda app and select your routine to check in securely. Answering this call does not log a dose.",
		);
	response.hangup();
	return response.toString();
}
