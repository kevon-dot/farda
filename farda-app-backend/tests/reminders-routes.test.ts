import express from "express";
import type { Server } from "node:http";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import twilio from "twilio";
import { ConsumerError } from "../src/reminders/policy";

vi.mock("../src/lib/prisma", () => ({ prisma: {} }));
// Route integration isolates the session resolver. Canonical auth tests exercise
// real session expiry/ownership; here a missing session must stop every route.
vi.mock("../src/middleware/isAuthenticated", () => ({
	isAuthenticated: (req: any, res: any, next: any) => {
		if (!req.get("X-Test-User"))
			return res.status(401).json({ error: "Unauthorized" });
		req.user = { id: req.get("X-Test-User") };
		next();
	},
}));
import {
	createReminderRouter,
	createVoiceWebhookRouter,
} from "../src/reminders/routes";
import { createRefillRouter } from "../src/refills/routes";
import type { ReminderService } from "../src/reminders/service";
import type { RefillService } from "../src/refills/service";

describe("reminder/refill HTTP boundaries", () => {
	let server: Server, base: string;
	const config = {
		enabled: true,
		accountSid: "AC" + "1".repeat(32),
		authToken: "test-token",
		from: "+15555550000",
		publicOrigin: "https://farda.example",
		allowedPrefixes: ["+1"],
		maxCallsPerHour: 20,
	};
	const reminders = {
		preferences: vi.fn(async (userId) => ({ userId })),
		savePreferences: vi.fn(),
		occurrence: vi.fn(),
		plan: vi.fn(),
		snooze: vi.fn(),
		webhook: vi.fn(async () => ({ permitted: true, optedOut: false })),
	};
	const refills = {
		list: vi.fn(async (userId) => ({ userId })),
		create: vi.fn(),
		status: vi.fn(),
		inventory: vi.fn(),
		count: vi.fn(),
		receipt: vi.fn(),
	};
	beforeAll(async () => {
		const app = express();
		app.use(express.json());
		app.use(express.urlencoded({ extended: false }));
		app.use(
			"/api",
			createVoiceWebhookRouter(reminders as unknown as ReminderService, config),
		);
		app.use(
			"/api",
			createReminderRouter(reminders as unknown as ReminderService),
		);
		app.use("/api", createRefillRouter(refills as unknown as RefillService));
		server = await new Promise<Server>((resolve) => {
			const s = app.listen(0, "127.0.0.1", () => resolve(s));
		});
		base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
	});
	afterAll(
		() =>
			new Promise<void>((resolve, reject) =>
				server.close((error) => (error ? reject(error) : resolve())),
			),
	);
	it("requires session on preferences and refills", async () => {
		expect((await fetch(base + "/api/reminders/preferences")).status).toBe(401);
		expect((await fetch(base + "/api/refills")).status).toBe(401);
	});
	it("passes session identity rather than a supplied user query", async () => {
		const result = await fetch(
			base + "/api/reminders/preferences?userId=other",
			{ headers: { "X-Test-User": "owner" } },
		);
		expect(await result.json()).toEqual({ userId: "owner" });
	});
	it("rejects malformed preference or client-controlled ownership before service", async () => {
		const result = await fetch(base + "/api/reminders/preferences", {
			method: "PUT",
			headers: { "X-Test-User": "owner", "Content-Type": "application/json" },
			body: JSON.stringify({
				userId: "other",
				callsEnabled: true,
				quietHoursStart: "99:99",
			}),
		});
		expect(result.status).toBe(400);
		expect(reminders.savePreferences).not.toHaveBeenCalled();
	});
	it("returns safe specific conflict messages and hides internal errors", async () => {
		refills.inventory.mockRejectedValueOnce(
			new ConsumerError(404, "Prescription not found."),
		);
		const one = await fetch(base + "/api/inventory/foreign", {
			headers: { "X-Test-User": "owner" },
		});
		expect(one.status).toBe(404);
		expect(await one.json()).toEqual({ error: "Prescription not found." });
		refills.inventory.mockRejectedValueOnce(
			new Error("secret health database details"),
		);
		const two = await fetch(base + "/api/inventory/p1", {
			headers: { "X-Test-User": "owner" },
		});
		expect(two.status).toBe(500);
		expect(JSON.stringify(await two.json())).not.toContain("secret");
	});
	it("rejects unsigned webhook before any ledger mutation", async () => {
		const result = await fetch(base + "/api/reminders/twilio/attempt/status", {
			method: "POST",
			body: new URLSearchParams({ AccountSid: config.accountSid }),
		});
		expect(result.status).toBe(403);
		expect(reminders.webhook).not.toHaveBeenCalled();
	});
	it("accepts canonical signed form callback without a consumer session", async () => {
		const path = "/api/reminders/twilio/attempt/status";
		const body = {
			AccountSid: config.accountSid,
			CallSid: "CA" + "2".repeat(32),
			To: "+15555550123",
			CallStatus: "completed",
			SequenceNumber: "3",
		};
		const signature = twilio.getExpectedTwilioSignature(
			config.authToken,
			config.publicOrigin + path,
			body,
		);
		const result = await fetch(base + path, {
			method: "POST",
			headers: { "X-Twilio-Signature": signature },
			body: new URLSearchParams(body),
		});
		expect(result.status).toBe(204);
		expect(reminders.webhook).toHaveBeenLastCalledWith(
			"attempt",
			body,
			"status",
		);
	});
});
