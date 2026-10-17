import {
	createCipheriv,
	createDecipheriv,
	createHmac,
	randomBytes,
	timingSafeEqual,
} from "node:crypto";

const VERSION = "v1";

export class TokenProtector {
	constructor(private readonly key: Buffer) {
		if (key.length !== 32)
			throw new Error("live_activity_encryption_key_invalid");
	}

	static fromBase64(value: string | undefined): TokenProtector | null {
		if (!value || !/^[A-Za-z0-9+/]{43}=$/.test(value)) return null;
		const key = Buffer.from(value, "base64");
		return key.length === 32 ? new TokenProtector(key) : null;
	}

	fingerprint(token: string): string {
		return createHmac("sha256", this.key)
			.update("farda-live-activity-token\0")
			.update(token, "utf8")
			.digest("base64url");
	}

	protect(token: string, context: string): string {
		const nonce = randomBytes(12);
		const cipher = createCipheriv("aes-256-gcm", this.key, nonce);
		cipher.setAAD(Buffer.from(context, "utf8"));
		const ciphertext = Buffer.concat([
			cipher.update(token, "utf8"),
			cipher.final(),
		]);
		return [
			VERSION,
			nonce.toString("base64url"),
			ciphertext.toString("base64url"),
			cipher.getAuthTag().toString("base64url"),
		].join(".");
	}

	unprotect(value: string, context: string): string {
		const parts = value.split(".");
		if (parts.length !== 4 || parts[0] !== VERSION)
			throw new Error("live_activity_token_unreadable");
		try {
			const nonce = Buffer.from(parts[1], "base64url");
			const ciphertext = Buffer.from(parts[2], "base64url");
			const tag = Buffer.from(parts[3], "base64url");
			if (nonce.length !== 12 || tag.length !== 16 || ciphertext.length === 0)
				throw new Error("invalid");
			const decipher = createDecipheriv("aes-256-gcm", this.key, nonce);
			decipher.setAAD(Buffer.from(context, "utf8"));
			decipher.setAuthTag(tag);
			return Buffer.concat([
				decipher.update(ciphertext),
				decipher.final(),
			]).toString("utf8");
		} catch {
			throw new Error("live_activity_token_unreadable");
		}
	}

	matches(token: string, fingerprint: string): boolean {
		const expected = Buffer.from(this.fingerprint(token));
		const actual = Buffer.from(fingerprint);
		return (
			expected.length === actual.length && timingSafeEqual(expected, actual)
		);
	}
}
