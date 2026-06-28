/******************************************************************************
 * PHI-safe redaction (GTM-512).
 *
 * `redact()` deep-clones a value and masks any property whose key matches a
 * PHI/secret denylist (case-insensitive). It also scrubs obvious secrets/PII
 * patterns (bearer tokens, emails) out of free-form strings before they are
 * logged. The function is recursion-safe (handles cycles + a depth limit),
 * special-cases `Error` objects (keeps name/message/stack only, never their
 * enumerable PHI props), Buffers, and is guaranteed to never throw.
 *
 * This is the single source of truth for "what counts as PHI/secret" in logs.
 ******************************************************************************/

/** Mask token written in place of any redacted value. */
export const REDACTED = "[REDACTED]";

/** Maximum nesting depth we will walk before collapsing to a placeholder. */
const MAX_DEPTH = 8;

/**
 * Keys (case-insensitive) whose VALUES must never be logged. Covers auth
 * secrets and the HIPAA PHI fields handled by this service (prescriptions,
 * contact info, clinical notes, mood, etc.).
 */
const DENYLIST_KEYS: ReadonlySet<string> = new Set(
	[
		// secrets / auth
		"password",
		"token",
		"accessToken",
		"refreshToken",
		"authorization",
		"cookie",
		"secret",
		"apiKey",
		"otp",
		"code",
		"sessionToken",
		"betterAuthSecret",
		// PII / PHI
		"phone",
		"phoneNumber",
		"email",
		"dob",
		"dateOfBirth",
		"name",
		"firstName",
		"lastName",
		"address",
		"ssn",
		// clinical PHI
		"medicationName",
		"dosageInstructions",
		"rxNumber",
		"prescription",
		"note",
		"notes",
		"mood",
	].map((k) => k.toLowerCase()),
);

function isDenied(key: string): boolean {
	return DENYLIST_KEYS.has(key.toLowerCase());
}

/******************************************************************************
 * Free-form string scrubbing
 ******************************************************************************/

// `Bearer <token>` / `Basic <creds>` style Authorization values.
const BEARER_RE = /\b(bearer|basic)\s+[A-Za-z0-9._\-+/=]+/gi;
// JWT-shaped tokens (three base64url segments).
const JWT_RE = /\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g;
// Email addresses.
const EMAIL_RE = /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/g;

/**
 * Scrub obvious secrets/PII out of a free-form string. Used both for top-level
 * string args and for every string value we encounter while walking an object.
 */
export function scrubString(input: string): string {
	if (typeof input !== "string" || input.length === 0) {
		return input;
	}
	try {
		return input
			.replace(BEARER_RE, REDACTED)
			.replace(JWT_RE, REDACTED)
			.replace(EMAIL_RE, REDACTED);
	} catch {
		return REDACTED;
	}
}

/******************************************************************************
 * Error handling
 ******************************************************************************/

interface RedactedError {
	name: string;
	message: string;
	stack?: string;
}

/**
 * Serialize an Error to its name/message/stack only. We deliberately drop ALL
 * enumerable own-properties (custom errors frequently hang PHI like the offending
 * request body or a user object off the error) and scrub the message/stack.
 */
function redactError(err: Error): RedactedError {
	const out: RedactedError = {
		name: typeof err.name === "string" ? err.name : "Error",
		message: scrubString(typeof err.message === "string" ? err.message : ""),
	};
	if (typeof err.stack === "string") {
		out.stack = scrubString(err.stack);
	}
	return out;
}

/******************************************************************************
 * Core recursive redactor
 ******************************************************************************/

function redactValue(
	value: unknown,
	depth: number,
	seen: WeakSet<object>,
): unknown {
	// Primitives.
	if (value === null || value === undefined) {
		return value;
	}
	const t = typeof value;
	if (t === "string") {
		return scrubString(value as string);
	}
	if (t === "number" || t === "boolean" || t === "bigint") {
		return value;
	}
	if (t === "function" || t === "symbol") {
		return `[${t}]`;
	}

	// Depth guard.
	if (depth > MAX_DEPTH) {
		return "[REDACTED:depth]";
	}

	// Errors — name/message/stack only, never enumerable props.
	if (value instanceof Error) {
		return redactError(value);
	}

	// Buffers / typed arrays — never log raw bytes (may carry PHI).
	if (typeof Buffer !== "undefined" && Buffer.isBuffer(value)) {
		return `[Buffer ${(value as Buffer).length} bytes]`;
	}
	if (ArrayBuffer.isView(value)) {
		return `[${(value as { constructor: { name: string } }).constructor.name}]`;
	}

	const obj = value as object;

	// Cycle guard.
	if (seen.has(obj)) {
		return "[Circular]";
	}
	seen.add(obj);

	try {
		// Arrays.
		if (Array.isArray(value)) {
			return value.map((item) => redactValue(item, depth + 1, seen));
		}

		// Dates → ISO string (a plain Date carries no PHI by itself, but it may sit
		// under a denied key, which is handled by the caller before recursion).
		if (value instanceof Date) {
			return value.toISOString();
		}

		// Maps / Sets → plain structures so they serialize.
		if (value instanceof Map) {
			const out: Record<string, unknown> = {};
			for (const [k, v] of value.entries()) {
				const key = String(k);
				out[key] = isDenied(key) ? REDACTED : redactValue(v, depth + 1, seen);
			}
			return out;
		}
		if (value instanceof Set) {
			return Array.from(value).map((item) =>
				redactValue(item, depth + 1, seen),
			);
		}

		// Plain objects.
		const out: Record<string, unknown> = {};
		for (const key of Object.keys(obj)) {
			let descriptorValue: unknown;
			try {
				descriptorValue = (obj as Record<string, unknown>)[key];
			} catch {
				// Getter threw — skip rather than crash.
				out[key] = "[unreadable]";
				continue;
			}
			out[key] = isDenied(key)
				? REDACTED
				: redactValue(descriptorValue, depth + 1, seen);
		}
		return out;
	} catch {
		return REDACTED;
	} finally {
		seen.delete(obj);
	}
}

/**
 * Deep-clone `value` with all PHI/secret keys masked and free-form strings
 * scrubbed. Never throws and never mutates the input.
 */
export function redact(value: unknown): unknown {
	try {
		return redactValue(value, 0, new WeakSet<object>());
	} catch {
		return REDACTED;
	}
}

/** Redact a variadic list of log arguments (one per logger call argument). */
export function redactArgs(args: unknown[]): unknown[] {
	return args.map((arg) => redact(arg));
}
