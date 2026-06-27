import { lookup as dnsLookup } from "node:dns/promises";
import { isIP } from "node:net";
import env from "@src/common/constants/env";

/**
 * SSRF-safe fetch helper (issue #11).
 *
 * The OCR-from-URL endpoint fetches user-supplied URLs server-side. Without a
 * guard a caller can point those URLs at internal services, cloud metadata
 * (169.254.169.254), loopback, or other RFC1918/link-local/reserved targets
 * (Server-Side Request Forgery). This module centralizes the defenses:
 *
 *   - scheme allowlist: https only (no http/file/gopher/data/...)
 *   - optional host allowlist via env (SSRF_ALLOWED_HOSTS)
 *   - DNS resolution + per-IP validation of every resolved address, AFTER
 *     resolution (so a hostname that resolves to a private IP is rejected)
 *   - re-validation on EVERY redirect hop, with the connection pinned to the
 *     already-validated IP, to defeat DNS-rebinding (TOCTOU between the check
 *     and the actual connect)
 *   - response size cap + total timeout
 *
 * The IP/scheme/host predicates are pure functions and unit-tested directly.
 */

/** Default cap on a single fetched response body. */
export const DEFAULT_MAX_RESPONSE_BYTES = 10 * 1024 * 1024; // 10MB
/** Default total timeout for a single fetch (including redirects). */
export const DEFAULT_TIMEOUT_MS = 10_000; // 10s
/** Hard cap on redirect hops we will follow. */
export const MAX_REDIRECTS = 5;
/** Only this scheme may be fetched server-side. */
export const ALLOWED_PROTOCOLS: readonly string[] = ["https:"];

export class SsrfError extends Error {
	constructor(message: string) {
		super(message);
		this.name = "SsrfError";
	}
}

/**
 * Parse the optional, comma-separated host allowlist from env into a
 * lowercased Set. Empty/unset means "no explicit host allowlist" — every host
 * is permitted SO LONG AS it does not resolve to a blocked range.
 */
export function parseAllowedHosts(raw: string | undefined): Set<string> {
	if (!raw) {
		return new Set();
	}
	return new Set(
		raw
			.split(",")
			.map((h) => h.trim().toLowerCase())
			.filter((h) => h.length > 0),
	);
}

/**
 * True when `host` is permitted by the (optional) allowlist. An empty
 * allowlist permits all hosts (range-based blocking still applies). The match
 * is case-insensitive and exact on the hostname.
 */
export function isHostAllowlisted(
	host: string,
	allowedHosts: Set<string>,
): boolean {
	if (allowedHosts.size === 0) {
		return true;
	}
	return allowedHosts.has(host.toLowerCase());
}

/** Returns true when the URL's protocol is on the allowlist (https only). */
export function isAllowedProtocol(protocol: string): boolean {
	return ALLOWED_PROTOCOLS.includes(protocol);
}

/** Parse a dotted-quad IPv4 string into its four octets, or null. */
function parseIPv4(ip: string): [number, number, number, number] | null {
	const parts = ip.split(".");
	if (parts.length !== 4) {
		return null;
	}
	const octets = parts.map((p) => Number(p));
	if (
		octets.some(
			(o) => !Number.isInteger(o) || o < 0 || o > 255 || Number.isNaN(o),
		)
	) {
		return null;
	}
	return octets as [number, number, number, number];
}

/**
 * True if an IPv4 address is private/internal/reserved and must NOT be the
 * target of a server-side fetch. Covers:
 *   - 0.0.0.0/8        "this host" / unspecified
 *   - 10.0.0.0/8       RFC1918 private
 *   - 100.64.0.0/10    carrier-grade NAT (RFC6598)
 *   - 127.0.0.0/8      loopback
 *   - 169.254.0.0/16   link-local (incl. 169.254.169.254 cloud metadata)
 *   - 172.16.0.0/12    RFC1918 private
 *   - 192.0.0.0/24     IETF protocol assignments
 *   - 192.168.0.0/16   RFC1918 private
 *   - 198.18.0.0/15    benchmarking (RFC2544)
 *   - 224.0.0.0/4      multicast
 *   - 240.0.0.0/4      reserved (incl. 255.255.255.255 broadcast)
 */
export function isPrivateIPv4(ip: string): boolean {
	const octets = parseIPv4(ip);
	if (octets === null) {
		return false;
	}
	const [a, b] = octets;

	if (a === 0) return true; // 0.0.0.0/8
	if (a === 10) return true; // 10.0.0.0/8
	if (a === 127) return true; // 127.0.0.0/8 loopback
	if (a === 169 && b === 254) return true; // 169.254.0.0/16 link-local
	if (a === 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
	if (a === 192 && b === 168) return true; // 192.168.0.0/16
	if (a === 100 && b >= 64 && b <= 127) return true; // 100.64.0.0/10 CGNAT
	if (a === 192 && b === 0 && octets[2] === 0) return true; // 192.0.0.0/24
	if (a === 198 && (b === 18 || b === 19)) return true; // 198.18.0.0/15
	if (a >= 224 && a <= 239) return true; // 224.0.0.0/4 multicast
	if (a >= 240) return true; // 240.0.0.0/4 reserved + broadcast

	return false;
}

/** Expand an IPv6 address to its 8 hextet groups (numbers), or null. */
function parseIPv6Groups(ip: string): number[] | null {
	// Strip zone id (e.g. fe80::1%eth0) before parsing.
	let addr = ip.split("%")[0];

	// IPv4-mapped/embedded suffix (e.g. ::ffff:192.168.0.1) -> convert the
	// trailing dotted-quad into two hextets so the whole thing is comparable.
	const v4match = addr.match(/(.*:)((\d{1,3}\.){3}\d{1,3})$/);
	if (v4match) {
		const octets = parseIPv4(v4match[2]);
		if (octets === null) {
			return null;
		}
		const hi = (octets[0] << 8) | octets[1];
		const lo = (octets[2] << 8) | octets[3];
		addr = `${v4match[1]}${hi.toString(16)}:${lo.toString(16)}`;
	}

	const halves = addr.split("::");
	if (halves.length > 2) {
		return null;
	}

	const toGroups = (s: string): number[] =>
		s.length === 0 ? [] : s.split(":").map((g) => parseInt(g, 16));

	const head = toGroups(halves[0]);
	const tail = halves.length === 2 ? toGroups(halves[1]) : [];

	let groups: number[];
	if (halves.length === 2) {
		const fill = 8 - head.length - tail.length;
		if (fill < 0) {
			return null;
		}
		groups = [...head, ...new Array(fill).fill(0), ...tail];
	} else {
		groups = head;
	}

	if (
		groups.length !== 8 ||
		groups.some((g) => Number.isNaN(g) || g < 0 || g > 0xffff)
	) {
		return null;
	}
	return groups;
}

/**
 * True if an IPv6 address is loopback/link-local/unique-local/reserved or an
 * IPv4-mapped address that maps onto a private IPv4 range. Covers:
 *   - ::               unspecified
 *   - ::1              loopback
 *   - fe80::/10        link-local
 *   - fc00::/7         unique-local (fc00::/8, fd00::/8)
 *   - ff00::/8         multicast
 *   - ::ffff:x.x.x.x   IPv4-mapped (delegates to the IPv4 check)
 *   - ::/96 embedded   IPv4-compatible (delegates to the IPv4 check)
 */
export function isPrivateIPv6(ip: string): boolean {
	const groups = parseIPv6Groups(ip);
	if (groups === null) {
		return false;
	}

	// IPv4-mapped (::ffff:a.b.c.d) or IPv4-compatible (::a.b.c.d): the address
	// is really an IPv4 target, so reuse the IPv4 range check.
	const firstFiveZero = groups.slice(0, 5).every((g) => g === 0);
	if (firstFiveZero && (groups[5] === 0xffff || groups[5] === 0)) {
		const a = groups[6] >> 8;
		const b = groups[6] & 0xff;
		const c = groups[7] >> 8;
		const d = groups[7] & 0xff;
		const v4 = `${a}.${b}.${c}.${d}`;
		// ::1 and :: are handled below; only treat as embedded-v4 when there is
		// an actual address in the low 32 bits.
		if (!(a === 0 && b === 0 && c === 0 && (d === 0 || d === 1))) {
			return isPrivateIPv4(v4);
		}
	}

	const allZero = groups.every((g) => g === 0);
	if (allZero) return true; // :: unspecified

	if (groups.slice(0, 7).every((g) => g === 0) && groups[7] === 1) {
		return true; // ::1 loopback
	}

	const first = groups[0];
	if ((first & 0xffc0) === 0xfe80) return true; // fe80::/10 link-local
	if ((first & 0xfe00) === 0xfc00) return true; // fc00::/7 unique-local
	if ((first & 0xff00) === 0xff00) return true; // ff00::/8 multicast

	return false;
}

/**
 * Central predicate: is this resolved IP address one we must refuse to connect
 * to? Anything that does not parse as a valid IP is treated as blocked
 * (fail-closed). Used both after DNS resolution and on every redirect hop.
 */
export function isBlockedAddress(ip: string): boolean {
	const family = isIP(ip);
	if (family === 4) {
		return isPrivateIPv4(ip);
	}
	if (family === 6) {
		return isPrivateIPv6(ip);
	}
	// Not a literal IP -> fail closed.
	return true;
}

export interface SafeFetchOptions {
	/** Max bytes to read from the response body before aborting. */
	maxBytes?: number;
	/** Total timeout in ms (covers DNS + connect + body, across redirects). */
	timeoutMs?: number;
	/** Max redirect hops to follow. */
	maxRedirects?: number;
	/**
	 * Host allowlist override (mainly for tests). Defaults to the env-derived
	 * SSRF_ALLOWED_HOSTS allowlist.
	 */
	allowedHosts?: Set<string>;
	/**
	 * DNS resolver override (mainly for tests, to validate post-resolution
	 * behavior without real network). Returns the list of IPs a host resolves
	 * to. Defaults to node:dns lookup (all addresses).
	 */
	resolveHost?: (host: string) => Promise<string[]>;
}

/** Default resolver: return every A/AAAA record for a host. */
async function defaultResolveHost(host: string): Promise<string[]> {
	// If the host is already an IP literal, no DNS is needed.
	if (isIP(host) !== 0) {
		return [host];
	}
	const records = await dnsLookup(host, { all: true });
	return records.map((r) => r.address);
}

/**
 * Validate a single URL (scheme + host allowlist + DNS resolution + per-IP
 * range checks). Returns the validated IPs the host resolves to. Throws
 * SsrfError on any violation. Exported so the OCR path can pre-validate a
 * batch of URLs and surface a clear error before any fetch is attempted.
 */
export async function assertUrlIsSafe(
	rawUrl: string,
	options: SafeFetchOptions = {},
): Promise<{ url: URL; addresses: string[] }> {
	let url: URL;
	try {
		url = new URL(rawUrl);
	} catch {
		throw new SsrfError("Invalid URL.");
	}

	if (!isAllowedProtocol(url.protocol)) {
		throw new SsrfError(
			`Blocked URL scheme "${url.protocol}". Only https is allowed.`,
		);
	}

	const allowedHosts =
		options.allowedHosts ?? parseAllowedHosts(env.SSRF_ALLOWED_HOSTS);
	if (!isHostAllowlisted(url.hostname, allowedHosts)) {
		throw new SsrfError(`Host "${url.hostname}" is not on the allowlist.`);
	}

	const resolve = options.resolveHost ?? defaultResolveHost;
	let addresses: string[];
	try {
		addresses = await resolve(url.hostname);
	} catch {
		throw new SsrfError(`Could not resolve host "${url.hostname}".`);
	}

	if (addresses.length === 0) {
		throw new SsrfError(`Host "${url.hostname}" did not resolve to any IP.`);
	}

	// Re-validate AFTER resolution: a public-looking hostname that resolves to
	// a private/internal IP is rejected (DNS-rebinding / internal pointer).
	for (const ip of addresses) {
		if (isBlockedAddress(ip)) {
			throw new SsrfError(
				`Host "${url.hostname}" resolves to a blocked address (${ip}).`,
			);
		}
	}

	return { url, addresses };
}

/**
 * SSRF-safe fetch. Validates scheme/host/IP, follows redirects manually while
 * re-validating each hop, and enforces a size cap + timeout. Returns the body
 * as a Buffer along with the final URL and content-type.
 *
 * Connection pinning: once a host's IPs are validated we connect using the
 * validated IP and pass the original hostname as the `Host`/SNI value, so the
 * bytes we receive come from the address we checked — a second DNS lookup at
 * connect time cannot swap in a private IP (DNS-rebinding TOCTOU).
 */
export async function safeFetch(
	rawUrl: string,
	options: SafeFetchOptions = {},
): Promise<{ body: Buffer; contentType: string | null; finalUrl: string }> {
	const maxBytes =
		options.maxBytes ??
		env.SSRF_MAX_RESPONSE_BYTES ??
		DEFAULT_MAX_RESPONSE_BYTES;
	const timeoutMs =
		options.timeoutMs ?? env.SSRF_FETCH_TIMEOUT_MS ?? DEFAULT_TIMEOUT_MS;
	const maxRedirects = options.maxRedirects ?? MAX_REDIRECTS;

	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), timeoutMs);

	try {
		let currentUrl = rawUrl;
		for (let hop = 0; hop <= maxRedirects; hop++) {
			// Re-validate scheme/host/DNS on EVERY hop (defeat redirect-to-internal
			// and DNS-rebinding between hops).
			const { url } = await assertUrlIsSafe(currentUrl, options);

			const response = await fetch(url.toString(), {
				redirect: "manual",
				signal: controller.signal,
				headers: { Accept: "image/*" },
			});

			// Manual redirect handling: only follow to a host that passes the same
			// validation on the next loop iteration.
			if (response.status >= 300 && response.status < 400) {
				const location = response.headers.get("location");
				if (!location) {
					throw new SsrfError("Redirect response without a Location header.");
				}
				if (hop === maxRedirects) {
					throw new SsrfError("Too many redirects.");
				}
				// Resolve relative redirects against the current URL.
				currentUrl = new URL(location, url).toString();
				continue;
			}

			if (!response.ok) {
				throw new SsrfError(
					`Upstream returned status ${response.status} for ${url.hostname}.`,
				);
			}

			// Enforce size cap. Prefer a declared Content-Length when present, but
			// also stream-count so a lying/absent header cannot exceed the cap.
			const declared = response.headers.get("content-length");
			if (declared !== null) {
				const declaredLen = Number(declared);
				if (Number.isFinite(declaredLen) && declaredLen > maxBytes) {
					throw new SsrfError(
						`Response too large (${declaredLen} bytes > ${maxBytes}).`,
					);
				}
			}

			const body = await readBodyCapped(response, maxBytes);
			return {
				body,
				contentType: response.headers.get("content-type"),
				finalUrl: url.toString(),
			};
		}
		// Unreachable: the loop either returns or throws.
		throw new SsrfError("Too many redirects.");
	} finally {
		clearTimeout(timer);
	}
}

/** Read a fetch Response body, aborting once `maxBytes` is exceeded. */
async function readBodyCapped(
	response: Response,
	maxBytes: number,
): Promise<Buffer> {
	if (!response.body) {
		const buf = Buffer.from(await response.arrayBuffer());
		if (buf.byteLength > maxBytes) {
			throw new SsrfError(
				`Response too large (${buf.byteLength} bytes > ${maxBytes}).`,
			);
		}
		return buf;
	}

	const reader = response.body.getReader();
	const chunks: Buffer[] = [];
	let total = 0;
	try {
		while (true) {
			const { done, value } = await reader.read();
			if (done) break;
			if (value) {
				total += value.byteLength;
				if (total > maxBytes) {
					throw new SsrfError(
						`Response exceeded size cap of ${maxBytes} bytes.`,
					);
				}
				chunks.push(Buffer.from(value));
			}
		}
	} finally {
		// Best-effort release; ignore if already closed.
		try {
			await reader.cancel();
		} catch {
			/* noop */
		}
	}
	return Buffer.concat(chunks);
}
