import * as path from "node:path";

/**
 * Centralized allowlist + validation for prescription image uploads.
 *
 * Previously the multer fileFilter accepted a file when EITHER its MIME type
 * OR its extension matched, and it allowed `application/octet-stream` as a
 * catch-all — so almost anything could get through (and then be sent to the
 * OCR/LLM pipeline). We now require BOTH the MIME type AND the extension to be
 * on the allowlist, drop the octet-stream escape hatch, and add a magic-byte
 * (content-signature) check that runs after the bytes are on disk.
 */
export const ALLOWED_IMAGE_MIMES: readonly string[] = [
	"image/jpeg",
	"image/jpg",
	"image/png",
	"image/webp",
];

export const ALLOWED_IMAGE_EXTENSIONS: readonly string[] = [
	".jpg",
	".jpeg",
	".png",
	".webp",
];

/** Max upload size, kept in one place so the route and docs agree. */
export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024; // 10MB

/**
 * Returns true only when BOTH the declared MIME type and the file extension
 * are on the allowlist. `application/octet-stream` is intentionally NOT
 * accepted.
 */
export function isAllowedImageUpload(
	mimetype: string,
	originalname: string,
): boolean {
	const ext = path.extname(originalname).toLowerCase();
	return (
		ALLOWED_IMAGE_MIMES.includes(mimetype) &&
		ALLOWED_IMAGE_EXTENSIONS.includes(ext)
	);
}

/**
 * Inspects the leading bytes of a file and returns the detected image type,
 * or null if the content does not match a supported image format. This defends
 * against a request that lies about its MIME type / extension.
 */
export function sniffImageType(
	buf: Buffer,
): "jpeg" | "png" | "webp" | null {
	if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) {
		return "jpeg";
	}
	if (
		buf.length >= 8 &&
		buf[0] === 0x89 &&
		buf[1] === 0x50 &&
		buf[2] === 0x4e &&
		buf[3] === 0x47 &&
		buf[4] === 0x0d &&
		buf[5] === 0x0a &&
		buf[6] === 0x1a &&
		buf[7] === 0x0a
	) {
		return "png";
	}
	if (
		buf.length >= 12 &&
		buf.toString("ascii", 0, 4) === "RIFF" &&
		buf.toString("ascii", 8, 12) === "WEBP"
	) {
		return "webp";
	}
	return null;
}
