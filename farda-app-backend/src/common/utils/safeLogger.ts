/******************************************************************************
 * PHI-safe logger (GTM-512).
 *
 * Thin wrapper over jet-logger that pipes every argument through `redact()`
 * before it is written, so PHI/secrets never reach stdout/log sinks. Prefer
 * these helpers over importing `jet-logger` directly anywhere a value could
 * carry a request body, user object, prescription, OTP, etc.
 ******************************************************************************/

import logger from "jet-logger";
import { redact } from "./redact";

/**
 * jet-logger's `info`/`warn`/`err` accept a single printable value. We redact
 * each argument and, when more than one is supplied, join their (already
 * redacted) serialized forms so call sites can keep using the familiar
 * `logFn("message", context)` shape.
 */
function format(args: unknown[]): unknown {
	const redacted = args.map((a) => redact(a));
	if (redacted.length === 1) {
		return redacted[0];
	}
	return redacted
		.map((a) => (typeof a === "string" ? a : safeStringify(a)))
		.join(" ");
}

function safeStringify(value: unknown): string {
	try {
		return JSON.stringify(value);
	} catch {
		return String(value);
	}
}

export function logInfo(...args: unknown[]): void {
	logger.info(format(args));
}

export function logWarn(...args: unknown[]): void {
	logger.warn(format(args));
}

export function logErr(...args: unknown[]): void {
	logger.err(format(args));
}

export const safeLogger = { logInfo, logWarn, logErr };

export default safeLogger;
