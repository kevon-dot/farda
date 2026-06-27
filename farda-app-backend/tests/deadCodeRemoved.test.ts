import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

/**
 * Regression guards for the #35 / #14 / #34 cleanup. These assert that the dead
 * scaffold / proxy / billing surfaces stay deleted, so they can't be silently
 * reintroduced. They read source on disk (no DB / Prisma client needed) so they
 * run deterministically in CI.
 */

const root = path.resolve(__dirname, "..");
const read = (rel: string) => readFileSync(path.join(root, rel), "utf8");

describe("#14 — dead FARDA_API_URL proxy removed", () => {
	it("env.ts no longer references FARDA_API_URL", () => {
		expect(read("src/common/constants/env.ts")).not.toContain("FARDA_API_URL");
	});

	it(".env.example no longer references FARDA_API_URL", () => {
		expect(read(".env.example")).not.toContain("FARDA_API_URL");
	});

	it("the proxy service and proxy routers are deleted", () => {
		expect(
			existsSync(path.join(root, "src/services/DeviceTrackingService.ts")),
		).toBe(false);
		expect(existsSync(path.join(root, "src/routes/DeviceUserRoutes.ts"))).toBe(
			false,
		);
		expect(existsSync(path.join(root, "src/routes/CaregiverRoutes.ts"))).toBe(
			false,
		);
	});
});

describe("#34 — Stripe config removed", () => {
	it(".env.example no longer references Stripe", () => {
		const envExample = read(".env.example");
		expect(envExample).not.toContain("STRIPE_SECRET_KEY");
		expect(envExample).not.toContain("STRIPE_SUCCESS_URL");
		expect(envExample).not.toContain("STRIPE_CANCEL_URL");
	});

	it("env.ts has no Stripe references", () => {
		expect(read("src/common/constants/env.ts").toUpperCase()).not.toContain(
			"STRIPE",
		);
	});
});

describe("#35 — numeric-id User scaffold removed", () => {
	it("the scaffold model/service/repo/routes are deleted", () => {
		for (const rel of [
			"src/models/User.model.ts",
			"src/models/common/types.ts",
			"src/services/UserService.ts",
			"src/repos/UserRepo.ts",
			"src/routes/UserRoutes.ts",
			"src/views/users.html",
			"src/public/stylesheets/users.css",
		]) {
			expect(existsSync(path.join(root, rel))).toBe(false);
		}
	});

	it("server.ts no longer serves the users.html HTML surface", () => {
		const server = read("src/server.ts");
		expect(server).not.toContain("users.html");
		expect(server).not.toContain("express.static");
	});
});
