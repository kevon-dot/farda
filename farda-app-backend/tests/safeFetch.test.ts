import { describe, expect, it } from "vitest";
import {
	assertUrlIsSafe,
	isAllowedProtocol,
	isBlockedAddress,
	isHostAllowlisted,
	isPrivateIPv4,
	isPrivateIPv6,
	parseAllowedHosts,
	SsrfError,
} from "../src/services/safeFetch";

describe("isAllowedProtocol (#11 scheme allowlist)", () => {
	it("allows https only", () => {
		expect(isAllowedProtocol("https:")).toBe(true);
	});
	it("rejects http and other schemes", () => {
		expect(isAllowedProtocol("http:")).toBe(false);
		expect(isAllowedProtocol("file:")).toBe(false);
		expect(isAllowedProtocol("gopher:")).toBe(false);
		expect(isAllowedProtocol("ftp:")).toBe(false);
		expect(isAllowedProtocol("data:")).toBe(false);
	});
});

describe("isPrivateIPv4 (#11 private/internal ranges)", () => {
	it("blocks loopback 127.0.0.0/8", () => {
		expect(isPrivateIPv4("127.0.0.1")).toBe(true);
		expect(isPrivateIPv4("127.255.255.255")).toBe(true);
	});
	it("blocks RFC1918 ranges", () => {
		expect(isPrivateIPv4("10.0.0.5")).toBe(true);
		expect(isPrivateIPv4("172.16.0.1")).toBe(true);
		expect(isPrivateIPv4("172.31.255.255")).toBe(true);
		expect(isPrivateIPv4("192.168.1.1")).toBe(true);
	});
	it("blocks link-local incl. cloud metadata 169.254.169.254", () => {
		expect(isPrivateIPv4("169.254.169.254")).toBe(true);
		expect(isPrivateIPv4("169.254.0.1")).toBe(true);
	});
	it("blocks 0.0.0.0/8, CGNAT, multicast, reserved", () => {
		expect(isPrivateIPv4("0.0.0.0")).toBe(true);
		expect(isPrivateIPv4("100.64.0.1")).toBe(true);
		expect(isPrivateIPv4("224.0.0.1")).toBe(true);
		expect(isPrivateIPv4("255.255.255.255")).toBe(true);
	});
	it("allows public addresses", () => {
		expect(isPrivateIPv4("8.8.8.8")).toBe(false);
		expect(isPrivateIPv4("1.1.1.1")).toBe(false);
		expect(isPrivateIPv4("172.15.0.1")).toBe(false); // just below 172.16/12
		expect(isPrivateIPv4("172.32.0.1")).toBe(false); // just above 172.16/12
		expect(isPrivateIPv4("93.184.216.34")).toBe(false); // example.com
	});
});

describe("isPrivateIPv6 (#11 ipv6 ranges)", () => {
	it("blocks loopback ::1 and unspecified ::", () => {
		expect(isPrivateIPv6("::1")).toBe(true);
		expect(isPrivateIPv6("::")).toBe(true);
	});
	it("blocks link-local fe80::/10 and unique-local fc00::/7", () => {
		expect(isPrivateIPv6("fe80::1")).toBe(true);
		expect(isPrivateIPv6("fd00::1")).toBe(true);
		expect(isPrivateIPv6("fc00::1")).toBe(true);
	});
	it("blocks ipv4-mapped private addresses", () => {
		expect(isPrivateIPv6("::ffff:127.0.0.1")).toBe(true);
		expect(isPrivateIPv6("::ffff:169.254.169.254")).toBe(true);
		expect(isPrivateIPv6("::ffff:10.0.0.1")).toBe(true);
	});
	it("allows public ipv6", () => {
		expect(isPrivateIPv6("2606:4700:4700::1111")).toBe(false); // cloudflare
		expect(isPrivateIPv6("2001:4860:4860::8888")).toBe(false); // google
	});
});

describe("isBlockedAddress (#11 fail-closed)", () => {
	it("blocks private, allows public, and fails closed on non-IPs", () => {
		expect(isBlockedAddress("169.254.169.254")).toBe(true);
		expect(isBlockedAddress("::1")).toBe(true);
		expect(isBlockedAddress("8.8.8.8")).toBe(false);
		// Not a literal IP -> fail closed.
		expect(isBlockedAddress("not-an-ip")).toBe(true);
		expect(isBlockedAddress("")).toBe(true);
	});
});

describe("parseAllowedHosts / isHostAllowlisted (#11 host allowlist)", () => {
	it("empty allowlist permits any host", () => {
		const allow = parseAllowedHosts(undefined);
		expect(allow.size).toBe(0);
		expect(isHostAllowlisted("example.com", allow)).toBe(true);
	});
	it("non-empty allowlist permits only listed hosts (case-insensitive)", () => {
		const allow = parseAllowedHosts(" cdn.example.com , imgs.test ");
		expect(isHostAllowlisted("cdn.example.com", allow)).toBe(true);
		expect(isHostAllowlisted("CDN.EXAMPLE.COM", allow)).toBe(true);
		expect(isHostAllowlisted("evil.com", allow)).toBe(false);
	});
});

describe("assertUrlIsSafe (#11 post-DNS validation, mocked resolver)", () => {
	// A resolver that returns whatever we tell it, so validation runs AFTER
	// resolution without any real network access.
	const resolverReturning =
		(...ips: string[]) =>
		async () =>
			ips;

	it("rejects http:// scheme", async () => {
		await expect(
			assertUrlIsSafe("http://example.com/x.png", {
				resolveHost: resolverReturning("93.184.216.34"),
			}),
		).rejects.toBeInstanceOf(SsrfError);
	});

	it("rejects 169.254.169.254 cloud-metadata target post-resolution", async () => {
		await expect(
			assertUrlIsSafe("https://metadata.example.com/latest", {
				resolveHost: resolverReturning("169.254.169.254"),
			}),
		).rejects.toThrow(/blocked address/);
	});

	it("rejects a host that resolves to 127.0.0.1", async () => {
		await expect(
			assertUrlIsSafe("https://rebind.example.com/x.png", {
				resolveHost: resolverReturning("127.0.0.1"),
			}),
		).rejects.toThrow(/blocked address/);
	});

	it("rejects a host that resolves to 10.x", async () => {
		await expect(
			assertUrlIsSafe("https://internal.example.com/x.png", {
				resolveHost: resolverReturning("10.1.2.3"),
			}),
		).rejects.toBeInstanceOf(SsrfError);
	});

	it("rejects a host that resolves to 192.168.x", async () => {
		await expect(
			assertUrlIsSafe("https://lan.example.com/x.png", {
				resolveHost: resolverReturning("192.168.1.10"),
			}),
		).rejects.toBeInstanceOf(SsrfError);
	});

	it("rejects a host that resolves to ::1", async () => {
		await expect(
			assertUrlIsSafe("https://v6.example.com/x.png", {
				resolveHost: resolverReturning("::1"),
			}),
		).rejects.toBeInstanceOf(SsrfError);
	});

	it("rejects when ANY resolved IP is private (mixed records)", async () => {
		await expect(
			assertUrlIsSafe("https://mixed.example.com/x.png", {
				resolveHost: resolverReturning("8.8.8.8", "10.0.0.1"),
			}),
		).rejects.toThrow(/blocked address/);
	});

	it("allows a normal public https host", async () => {
		const { url, addresses } = await assertUrlIsSafe(
			"https://cdn.example.com/rx.png",
			{ resolveHost: resolverReturning("93.184.216.34") },
		);
		expect(url.hostname).toBe("cdn.example.com");
		expect(addresses).toContain("93.184.216.34");
	});

	it("enforces the optional host allowlist", async () => {
		const opts = {
			resolveHost: resolverReturning("93.184.216.34"),
			allowedHosts: parseAllowedHosts("trusted.example.com"),
		};
		await expect(
			assertUrlIsSafe("https://untrusted.example.com/x.png", opts),
		).rejects.toThrow(/allowlist/);
		await expect(
			assertUrlIsSafe("https://trusted.example.com/x.png", opts),
		).resolves.toBeTruthy();
	});

	it("rejects a host that fails to resolve", async () => {
		await expect(
			assertUrlIsSafe("https://nxdomain.example.com/x.png", {
				resolveHost: async () => {
					throw new Error("ENOTFOUND");
				},
			}),
		).rejects.toThrow(/resolve/);
	});
});
