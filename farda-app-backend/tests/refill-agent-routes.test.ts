import express from "express";
import type { Server } from "node:http";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import type { RefillAgentService } from "../src/refills/agent";
import type { RefillService } from "../src/refills/service";

const counters = vi.hoisted(() => new Map<string, number>());
vi.mock("../src/lib/prisma", () => ({
	prisma: {
		$transaction: async (items: Promise<unknown>[]) => Promise.all(items),
		apiRateLimit: {
			upsert: async ({ where }: { where: { key: string } }) => {
				const count = (counters.get(where.key) ?? 0) + 1;
				counters.set(where.key, count);
				return { count };
			},
			deleteMany: async () => ({ count: 0 }),
		},
	},
}));
vi.mock("../src/middleware/isAuthenticated", () => ({
	isAuthenticated: (req: any, res: any, next: any) => {
		if (!req.get("X-Test-User"))
			return res.status(401).json({ error: "Unauthorized" });
		req.user = { id: req.get("X-Test-User") };
		next();
	},
}));
import { createRefillRouter } from "../src/refills/routes";

describe("refill agent HTTP contracts", () => {
	let server: Server, base: string;
	const agent = {
		review: vi.fn(async (userId: string) => ({ userId })),
		submit: vi.fn(async () => ({ ok: true })),
		refresh: vi.fn(async () => ({ ok: true })),
	};
	const headers = {
		"X-Test-User": "owner",
		"Content-Type": "application/json",
	};
	const input = {
		reviewToken: "a1074569-f4c3-48e8-9daf-1786ebac4521",
		confirmed: true,
		idempotencyKey: "request-12345",
	};
	beforeAll(async () => {
		const app = express();
		app.use(express.json());
		app.use(
			"/api",
			createRefillRouter(
				{} as RefillService,
				agent as unknown as RefillAgentService,
			),
		);
		server = await new Promise((resolve) => {
			const listener = app.listen(0, "127.0.0.1", () => resolve(listener));
		});
		base = `http://127.0.0.1:${(server.address() as { port: number }).port}/api/refills/agent/rx`;
	});
	afterAll(
		() =>
			new Promise<void>((resolve, reject) =>
				server.close((error) => (error ? reject(error) : resolve())),
			),
	);
	it("blocks all three endpoints without an authenticated session", async () => {
		expect((await fetch(base)).status).toBe(401);
		for (const suffix of ["/submit", "/refresh"])
			expect(
				(
					await fetch(base + suffix, {
						method: "POST",
						headers: { "Content-Type": "application/json" },
						body: JSON.stringify(input),
					})
				).status,
			).toBe(401);
		expect(agent.submit).not.toHaveBeenCalled();
	});
	it("uses session identity and sets no-store for private review data", async () => {
		const response = await fetch(base + "?userId=another", { headers });
		expect(response.headers.get("Cache-Control")).toBe("no-store");
		expect(await response.json()).toEqual({ userId: "owner" });
	});
	it("rejects omitted confirmation, provider IDs and ownership injection", async () => {
		for (const body of [
			{ ...input, confirmed: false },
			{ ...input, patientId: "other" },
			{ ...input, userId: "other" },
		]) {
			expect(
				(
					await fetch(base + "/submit", {
						method: "POST",
						headers,
						body: JSON.stringify(body),
					})
				).status,
			).toBe(400);
		}
		expect(agent.submit).not.toHaveBeenCalled();
		expect(
			(
				await fetch(base + "/refresh", {
					method: "POST",
					headers,
					body: JSON.stringify({ providerOrderId: "other" }),
				})
			).status,
		).toBe(400);
		expect(agent.refresh).not.toHaveBeenCalled();
	});
	it("passes only validated input to submit and enforces the shared database rate limit", async () => {
		counters.clear();
		for (let index = 0; index < 10; index++)
			expect(
				(
					await fetch(base + "/submit", {
						method: "POST",
						headers,
						body: JSON.stringify(input),
					})
				).status,
			).toBe(200);
		const blocked = await fetch(base + "/submit", {
			method: "POST",
			headers,
			body: JSON.stringify(input),
		});
		expect(blocked.status).toBe(429);
		expect(blocked.headers.get("Retry-After")).not.toBeNull();
		expect(agent.submit).toHaveBeenLastCalledWith("owner", "rx", input);
		expect(agent.submit).toHaveBeenCalledTimes(10);
	});
});
