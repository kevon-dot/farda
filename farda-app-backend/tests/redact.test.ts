import { REDACTED, redact, scrubString } from "@src/common/utils/redact";
import { describe, expect, it } from "vitest";

/**
 * Tests for the PHI-safe redactor (GTM-512). The redactor is the single source
 * of truth for "what counts as PHI/secret" in logs, so these assertions pin the
 * denylist behavior, recursion safety (cycles/depth), Error handling, and the
 * free-form string scrubbing.
 */

describe("redact - denylist keys", () => {
	it("masks denylisted keys at the top level (case-insensitive)", () => {
		const out = redact({
			password: "hunter2",
			Token: "abc",
			ACCESSTOKEN: "x",
			phone: "+15551234567",
			normal: "keep-me",
		}) as Record<string, unknown>;

		expect(out.password).toBe(REDACTED);
		expect(out.Token).toBe(REDACTED);
		expect(out.ACCESSTOKEN).toBe(REDACTED);
		expect(out.phone).toBe(REDACTED);
		expect(out.normal).toBe("keep-me");
	});

	it("masks PHI/clinical keys", () => {
		const out = redact({
			medicationName: "Atorvastatin",
			dosageInstructions: "Take 1 daily",
			rxNumber: "RX12345",
			prescription: { foo: "bar" },
			notes: "patient note",
			mood: "anxious",
			dateOfBirth: "1990-01-01",
			ssn: "123-45-6789",
		}) as Record<string, unknown>;

		for (const k of [
			"medicationName",
			"dosageInstructions",
			"rxNumber",
			"prescription",
			"notes",
			"mood",
			"dateOfBirth",
			"ssn",
		]) {
			expect(out[k]).toBe(REDACTED);
		}
	});

	it("masks denylisted keys at ALL nesting levels", () => {
		const out = redact({
			level1: {
				safe: "ok",
				level2: {
					email: "a@b.com",
					level3: { sessionToken: "deep-secret", keep: 1 },
				},
			},
		}) as any;

		expect(out.level1.safe).toBe("ok");
		expect(out.level1.level2.email).toBe(REDACTED);
		expect(out.level1.level2.level3.sessionToken).toBe(REDACTED);
		expect(out.level1.level2.level3.keep).toBe(1);
	});

	it("masks denylisted keys inside arrays of objects", () => {
		const out = redact({
			users: [
				{ name: "Alice", id: "u1" },
				{ name: "Bob", id: "u2" },
			],
		}) as any;

		expect(out.users[0].name).toBe(REDACTED);
		expect(out.users[0].id).toBe("u1");
		expect(out.users[1].name).toBe(REDACTED);
		expect(out.users[1].id).toBe("u2");
	});

	it("preserves non-PHI keys and primitive values", () => {
		const out = redact({
			status: 200,
			ok: true,
			count: 3,
			path: "/api/refills",
		});
		expect(out).toEqual({
			status: 200,
			ok: true,
			count: 3,
			path: "/api/refills",
		});
	});
});

describe("redact - Error objects", () => {
	it("keeps name + message but drops enumerable PHI props", () => {
		const err = new Error("boom") as Error & Record<string, unknown>;
		err.phone = "+15551234567";
		err.token = "secret-token";
		err.requestBody = { password: "p" };

		const out = redact(err) as Record<string, unknown>;

		expect(out.name).toBe("Error");
		expect(out.message).toBe("boom");
		expect(typeof out.stack).toBe("string");
		// PHI hung off the error must NOT survive.
		expect(out.phone).toBeUndefined();
		expect(out.token).toBeUndefined();
		expect(out.requestBody).toBeUndefined();
		expect(JSON.stringify(out)).not.toContain("+15551234567");
		expect(JSON.stringify(out)).not.toContain("secret-token");
	});

	it("scrubs secrets/emails embedded in an error message", () => {
		const out = redact(
			new Error("login failed for jane@example.com with Bearer abc.def.ghi"),
		) as Record<string, unknown>;

		expect(out.message).not.toContain("jane@example.com");
		expect(out.message).not.toContain("Bearer abc.def.ghi");
		expect(out.message).toContain(REDACTED);
	});
});

describe("redact - recursion safety", () => {
	it("does not hang on a cyclic object", () => {
		const a: Record<string, unknown> = { name: "x", safe: 1 };
		a.self = a;

		const out = redact(a) as Record<string, unknown>;
		expect(out.safe).toBe(1);
		expect(out.name).toBe(REDACTED);
		expect(out.self).toBe("[Circular]");
	});

	it("collapses excessively deep nesting instead of recursing forever", () => {
		let node: Record<string, unknown> = { value: 1 };
		for (let i = 0; i < 50; i++) {
			node = { child: node };
		}
		// Must not throw / overflow.
		const out = redact(node);
		expect(JSON.stringify(out)).toContain("[REDACTED:depth]");
	});

	it("never throws on a value whose getter throws", () => {
		const obj = {
			safe: 1,
			get explode(): never {
				throw new Error("getter blew up");
			},
		};
		expect(() => redact(obj)).not.toThrow();
		const out = redact(obj) as Record<string, unknown>;
		expect(out.safe).toBe(1);
	});
});

describe("redact - buffers", () => {
	it("never logs raw buffer bytes", () => {
		const out = redact({ blob: Buffer.from("PHI bytes here") }) as any;
		expect(typeof out.blob).toBe("string");
		expect(out.blob).toContain("Buffer");
		expect(out.blob).not.toContain("PHI bytes here");
	});
});

describe("scrubString", () => {
	it("scrubs bearer tokens", () => {
		expect(scrubString("Authorization: Bearer eyJabc.def.ghi")).not.toContain(
			"eyJabc.def.ghi",
		);
		expect(scrubString("Bearer sometoken123")).toBe(REDACTED);
	});

	it("scrubs emails", () => {
		const out = scrubString("contact jane.doe@example.com please");
		expect(out).not.toContain("jane.doe@example.com");
		expect(out).toContain(REDACTED);
	});

	it("scrubs JWT-shaped tokens", () => {
		const jwt = "eyJhbGciOi.eyJzdWIiOi.SflKxwRJSM";
		expect(scrubString(`token=${jwt}`)).not.toContain(jwt);
	});

	it("leaves clean strings untouched", () => {
		expect(scrubString("GET /api/refills 200")).toBe("GET /api/refills 200");
	});
});
