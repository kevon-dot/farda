import * as fs from "node:fs";
import * as path from "node:path";
import { describe, expect, it } from "vitest";
import {
	ALLOWED_IMAGE_EXTENSIONS,
	ALLOWED_IMAGE_MIMES,
	isAllowedImageUpload,
	sniffImageType,
} from "../src/routes/uploadFilter";

describe("isAllowedImageUpload (#49 upload filter)", () => {
	it("accepts a real image MIME + matching extension", () => {
		expect(isAllowedImageUpload("image/jpeg", "rx.jpg")).toBe(true);
		expect(isAllowedImageUpload("image/png", "scan.PNG")).toBe(true);
		expect(isAllowedImageUpload("image/webp", "label.webp")).toBe(true);
	});

	it("rejects application/octet-stream (the old catch-all)", () => {
		expect(isAllowedImageUpload("application/octet-stream", "rx.jpg")).toBe(
			false,
		);
	});

	it("requires BOTH mime and extension (not either/or)", () => {
		// Good MIME, bad extension
		expect(isAllowedImageUpload("image/png", "payload.exe")).toBe(false);
		// Bad MIME, good extension
		expect(isAllowedImageUpload("text/html", "evil.png")).toBe(false);
	});

	it("rejects unrelated types", () => {
		expect(isAllowedImageUpload("application/pdf", "doc.pdf")).toBe(false);
		expect(isAllowedImageUpload("text/plain", "notes.txt")).toBe(false);
	});

	it("keeps the allowlists free of octet-stream", () => {
		expect(ALLOWED_IMAGE_MIMES).not.toContain("application/octet-stream");
		expect(ALLOWED_IMAGE_EXTENSIONS).toContain(".jpg");
	});
});

describe("sniffImageType (#49 magic-byte validation)", () => {
	it("detects JPEG/PNG/WebP from their signatures", () => {
		expect(sniffImageType(Buffer.from([0xff, 0xd8, 0xff, 0xe0]))).toBe("jpeg");
		expect(
			sniffImageType(
				Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
			),
		).toBe("png");
		const webp = Buffer.concat([
			Buffer.from("RIFF", "ascii"),
			Buffer.from([0, 0, 0, 0]),
			Buffer.from("WEBP", "ascii"),
		]);
		expect(sniffImageType(webp)).toBe("webp");
	});

	it("returns null for non-image / spoofed content", () => {
		expect(sniffImageType(Buffer.from("#!/bin/sh\nrm -rf", "ascii"))).toBe(
			null,
		);
		expect(sniffImageType(Buffer.from("<html>", "ascii"))).toBe(null);
		expect(sniffImageType(Buffer.from([]))).toBe(null);
	});
});

describe("build tooling (#49 package.json)", () => {
	const pkg = JSON.parse(
		fs.readFileSync(path.join(__dirname, "..", "package.json"), "utf8"),
	);

	it("defines the lint script the build used to reference", () => {
		expect(pkg.scripts.lint).toBeDefined();
	});

	it("build no longer invokes an undefined `npm run lint`", () => {
		expect(pkg.scripts.build).toBeDefined();
		expect(pkg.scripts.build).not.toContain("npm run lint");
	});

	it("settles on pnpm as the package manager", () => {
		expect(pkg.packageManager).toMatch(/^pnpm@/);
	});
});
