import express from "express";
import type { Server } from "node:http";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

vi.mock("../src/lib/prisma", () => ({ prisma: {} }));
vi.mock("../src/middleware/isAuthenticated", () => ({
	isAuthenticated: (req: any, res: any, next: any) => {
		if (!req.get("X-Test-User"))
			return res.status(401).json({ error: "Unauthorized" });
		req.user = { id: req.get("X-Test-User"), sessionId: "session-owner" };
		next();
	},
}));

import { createLiveActivityRouter } from "../src/live-activities/routes";
import type { LiveActivityDeliveryService } from "../src/live-activities/service";

describe("Live Activity registration HTTP boundary", () => {
	let server: Server;
	let base: string;
	const service = {
		registerInstallation: vi.fn(async () => ({ registered: true })),
		registerActivity: vi.fn(async () => ({ registered: true })),
		revokeInstallation: vi.fn(async () => undefined),
	};
	beforeAll(async () => {
		const app = express();
		app.use(express.json());
		app.use(
			"/api",
			createLiveActivityRouter(
				service as unknown as LiveActivityDeliveryService,
			),
		);
		server = await new Promise<Server>((resolve) => {
			const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
		});
		base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
	});
	afterAll(
		() =>
			new Promise<void>((resolve, reject) =>
				server.close((error) => (error ? reject(error) : resolve())),
			),
	);

	it("requires authentication before accepting a bearer token", async () => {
		const response = await fetch(
			`${base}/api/live-activities/tokens/push-to-start`,
			{
				method: "PUT",
				headers: { "content-type": "application/json" },
				body: JSON.stringify({ installationId, token }),
			},
		);
		expect(response.status).toBe(401);
		expect(service.registerInstallation).not.toHaveBeenCalled();
	});

	it("derives ownership from the session and rejects extra identity fields", async () => {
		const response = await fetch(
			`${base}/api/live-activities/tokens/push-to-start`,
			{
				method: "PUT",
				headers: {
					"content-type": "application/json",
					"X-Test-User": "owner",
				},
				body: JSON.stringify({ installationId, token, userId: "other" }),
			},
		);
		expect(response.status).toBe(400);
		expect(service.registerInstallation).not.toHaveBeenCalled();
	});

	it("passes the authenticated owner and emits no token in the response", async () => {
		const response = await fetch(
			`${base}/api/live-activities/tokens/push-to-start`,
			{
				method: "PUT",
				headers: {
					"content-type": "application/json",
					"X-Test-User": "owner",
				},
				body: JSON.stringify({ installationId, token }),
			},
		);
		expect(response.status).toBe(200);
		expect(service.registerInstallation).toHaveBeenCalledWith(
			"owner",
			"session-owner",
			{
				installationId,
				token,
			},
		);
		expect(await response.text()).not.toContain(token);
	});
});

const token = "cd".repeat(32);
const installationId = "123e4567-e89b-42d3-a456-426614174000";
