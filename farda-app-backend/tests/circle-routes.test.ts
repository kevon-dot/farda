import express from "express";
import type { Server } from "node:http";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import type { CircleService } from "../src/circle/service";

vi.mock("../src/lib/prisma", () => ({ prisma: { apiRateLimit: { upsert: async () => ({ count: 1 }), deleteMany: async () => ({ count: 0 }) }, $transaction: async (values: Array<Promise<unknown>>) => Promise.all(values) } }));
import { createCircleRouter } from "../src/circle/routes";

describe("Circle HTTP contract", () => {
  let server: Server;
  let base: string;
  const circle = {
    overview: vi.fn(async () => ({ pending: [], members: [] })),
    received: vi.fn(async () => ({ invitations: [] })),
    invite: vi.fn(async (_user, _phone, permissions) => ({ status: "awaiting_acceptance", invitation: { id: "invite-1", inviteCode: "a".repeat(32), expiresAt: new Date("2026-10-23T00:00:00Z"), permissions } })),
    accept: vi.fn(async () => ({ status: "accepted" })), update: vi.fn(async (_u, id, permissions) => ({ id, permissions })),
    remove: vi.fn(), cancel: vi.fn(), decline: vi.fn(), shared: vi.fn(async () => ({ circles: [] })), leave: vi.fn(), routine: vi.fn(),
  };
  beforeAll(async () => {
    const app = express(); app.use(express.json()); app.use((req, _res, next) => { req.user = { id: "account-a" }; next(); }); app.use("/api", createCircleRouter(circle as unknown as CircleService));
    server = await new Promise(resolve => { const value = app.listen(0, "127.0.0.1", () => resolve(value)); });
    base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  });
  afterAll(() => new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())));

  it("returns the one-time invitation shape without claiming delivery", async () => {
    const response = await fetch(`${base}/api/circle/invitations`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ recipientPhone: "+15550000002", permissions: { doseStatus: true, reminders: true } }) });
    expect(response.status).toBe(202);
    expect(await response.json()).toMatchObject({ status: "awaiting_acceptance", invitation: { id: "invite-1", inviteCode: expect.any(String), permissions: { doseStatus: true, reminders: true } } });
    expect(circle.invite).toHaveBeenCalledWith("account-a", "+15550000002", { doseStatus: true, reminders: true });
  });

  it("allows an owner to pause all sharing through a member update", async () => {
    const response = await fetch(`${base}/api/circle/members/member-1`, { method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify({ doseStatus: false, reminders: false }) });
    expect(response.status).toBe(200);
    expect(circle.update).toHaveBeenCalledWith("account-a", "member-1", { doseStatus: false, reminders: false });
  });

  it("rejects malformed invite permissions before calling the service", async () => {
    const calls = circle.invite.mock.calls.length;
    const response = await fetch(`${base}/api/circle/invitations`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ recipientPhone: "+15550000002", permissions: { doseStatus: false, reminders: false } }) });
    expect(response.status).toBe(400);
    expect(circle.invite).toHaveBeenCalledTimes(calls);
  });
});
