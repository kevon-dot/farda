// ============================================
// A3 — Per-device credential storage (encrypted-at-rest)
// ============================================
// Each provisioned vial has its OWN symmetric secret used to HMAC its events.
//
// Storage choice — why encryption, not a one-way hash:
//   HMAC verification on the server must RE-COMPUTE the signature, which
//   requires the original secret. A one-way hash (bcrypt/SHA) is therefore
//   impossible here — you cannot HMAC with a digest you can't reverse. So the
//   secret is stored ENCRYPTED-AT-REST with AES-256-GCM under a server-held
//   master key (DEVICE_SECRET_ENC_KEY, never in the DB). At rest the database
//   only holds ciphertext + iv + auth tag; an attacker with DB-only access
//   cannot forge device events. The plaintext secret is decrypted in memory
//   only at the moment a signature is verified.
//
// The secret is handed to the device exactly ONCE at provisioning time (issue)
// and on each rotation. The device stores it in secure flash; the backend
// stores only the ciphertext.

const crypto = require("crypto");
const config = require("../config/config");

const ALGORITHM = "aes-256-gcm";
const SECRET_BYTES = 32; // 256-bit device secret
const IV_BYTES = 12; // standard GCM nonce length

/**
 * Derive the 32-byte AES master key from config. Accepts either a 64-char hex
 * string or any passphrase (hashed to 32 bytes via SHA-256). Throws if no key
 * is configured so the system fails closed rather than using a default.
 *
 * @returns {Buffer} 32-byte key
 */
function getMasterKey() {
  // Read the env var directly (with the config value as a fallback) so the key
  // can be provisioned/rotated without a process restart and so tests can set
  // it after config was first loaded.
  const raw = process.env.DEVICE_SECRET_ENC_KEY || config.device.secretEncKey;
  if (!raw || typeof raw !== "string" || raw.length === 0) {
    throw new Error(
      "DEVICE_SECRET_ENC_KEY is not configured. Per-device credentials cannot be encrypted/decrypted."
    );
  }
  if (/^[0-9a-fA-F]{64}$/.test(raw)) {
    return Buffer.from(raw, "hex");
  }
  // Passphrase fallback: deterministic 32-byte key.
  return crypto.createHash("sha256").update(raw, "utf8").digest();
}

/**
 * Generate a fresh random per-device secret (hex string).
 * @returns {string} 64-char lowercase hex (256-bit)
 */
function generateDeviceSecret() {
  return crypto.randomBytes(SECRET_BYTES).toString("hex");
}

/**
 * Encrypt a plaintext device secret for storage.
 *
 * @param {string} plaintextSecret  hex secret from generateDeviceSecret()
 * @returns {{ ciphertext: string, iv: string, tag: string }} all hex
 */
function encryptSecret(plaintextSecret) {
  const key = getMasterKey();
  const iv = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv(ALGORITHM, key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(plaintextSecret, "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return {
    ciphertext: ciphertext.toString("hex"),
    iv: iv.toString("hex"),
    tag: tag.toString("hex"),
  };
}

/**
 * Decrypt a stored device secret back to its plaintext hex form.
 *
 * @param {{ ciphertext: string, iv: string, tag: string }} stored
 * @returns {string} the plaintext hex secret
 */
function decryptSecret(stored) {
  if (!stored || !stored.ciphertext || !stored.iv || !stored.tag) {
    throw new Error("Encrypted secret is missing ciphertext/iv/tag");
  }
  const key = getMasterKey();
  const decipher = crypto.createDecipheriv(ALGORITHM, key, Buffer.from(stored.iv, "hex"));
  decipher.setAuthTag(Buffer.from(stored.tag, "hex"));
  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(stored.ciphertext, "hex")),
    decipher.final(),
  ]);
  return plaintext.toString("utf8");
}

module.exports = {
  ALGORITHM,
  SECRET_BYTES,
  generateDeviceSecret,
  encryptSecret,
  decryptSecret,
  getMasterKey,
};
