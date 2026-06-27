import * as fs from "node:fs";
import * as path from "node:path";
import type { Request, Response } from "express";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Tests for the HIPAA PHI audit trail (GTM-512, GitHub #6).
 *
 * No live DB: `prisma` is mocked with `vi.mock` so the suite is deterministic
 * and CI-friendly (no Postgres / credentials).
 */

const { prismaMock } = vi.hoisted(() => {
	const rows: Array<Record<string, unknown>> = [];
	const prismaMock = {
		__rows: rows,
		auditLog: {
			// Returns the most-recently-created row to chain off (desc order).
			findFirst: vi.fn(async () =>
				rows.length ? rows[rows.length - 1] : null,
			),
			create: vi.fn(async (args: { data: Record<string, unknown> }) => {
				const row = { id: `audit-${rows.length + 1}`, ...args.data };
				rows.push(row);
				return row;
			}),
		},
		// Minimal surfaces used by the OcrRoutes handler under test.
		user: { findUnique: vi.fn(async () => ({ id: "user-1" })) },
		prescription: {
			create: vi.fn(async (args: { data: { userId: string } }) => ({
				id: "rx-1",
				userId: args.data.userId,
				medicines: [],
			})),
			findMany: vi.fn(async () => []),
		},
		medicine: { createMany: vi.fn(async () => ({ count: 0 })) },
		dose: {
			createMany: vi.fn(async () => ({ count: 0 })),
			findMany: vi.fn(async () => []),
		},
	};
	return { prismaMock };
});

vi.mock("@src/lib/prisma", () => ({ prisma: prismaMock }));

import OcrRoutes from "@src/routes/OcrRoutes";
import { recordAccess } from "@src/services/AuditService";

function makeRes() {
	const res: Partial<Response> & { statusCode?: number; body?: unknown } = {};
	res.status = vi.fn((code: number) => {
		res.statusCode = code;
		return res as Response;
	}) as unknown as Response["status"];
	res.json = vi.fn((payload: unknown) => {
		res.body = payload;
		return res as Response;
	}) as unknown as Response["json"];
	return res as Response & { statusCode?: number; body?: unknown };
}

describe("AuditService.recordAccess", () => {
	beforeEach(() => {
		prismaMock.__rows.length = 0;
		vi.clearAllMocks();
	});

	it("inserts a row with the expected action/resourceType/resourceId and a non-empty hash", async () => {
		await recordAccess({
			actorUserId: "user-1",
			action: "READ",
			resourceType: "Prescription",
			resourceId: "rx-1",
		});

		expect(prismaMock.auditLog.create).toHaveBeenCalledTimes(1);
		const data = (
			prismaMock.auditLog.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(data.action).toBe("READ");
		expect(data.resourceType).toBe("Prescription");
		expect(data.resourceId).toBe("rx-1");
		expect(typeof data.hash).toBe("string");
		expect((data.hash as string).length).toBeGreaterThan(0);
		// First row has no predecessor.
		expect(data.prevHash).toBeNull();
	});

	it("chains each new hash off the previous row's hash", async () => {
		await recordAccess({
			actorUserId: "user-1",
			action: "CREATE",
			resourceType: "Prescription",
			resourceId: "rx-1",
		});
		await recordAccess({
			actorUserId: "user-1",
			action: "READ",
			resourceType: "Dose",
			resourceId: null,
		});

		const first = (
			prismaMock.auditLog.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		const second = (
			prismaMock.auditLog.create.mock.calls[1][0] as {
				data: Record<string, unknown>;
			}
		).data;

		// The second row's prevHash is the first row's hash (the chain link).
		expect(second.prevHash).toBe(first.hash);
		expect(second.hash).not.toBe(first.hash);
	});

	it("does NOT throw when the insert fails (fail-safe / fail-open)", async () => {
		prismaMock.auditLog.create.mockRejectedValueOnce(new Error("db down"));
		await expect(
			recordAccess({
				actorUserId: "user-1",
				action: "READ",
				resourceType: "Prescription",
			}),
		).resolves.toBeUndefined();
	});

	it("records NO PHI values -- only ids/types/action/metadata", async () => {
		await recordAccess({
			actorUserId: "user-1",
			action: "UPDATE",
			resourceType: "Dose",
			resourceId: "dose-1",
			metadata: { count: 2 },
		});

		const data = (
			prismaMock.auditLog.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		// Only the allowlisted, non-PHI keys are persisted.
		expect(Object.keys(data).sort()).toEqual(
			[
				"action",
				"actorUserId",
				"hash",
				"ip",
				"metadata",
				"prevHash",
				"resourceId",
				"resourceType",
				"userAgent",
			].sort(),
		);
		// Serialised row contains no PHI-ish free text (no medication/mood/note).
		const serialized = JSON.stringify(data);
		expect(serialized).not.toMatch(/mood|note|medication|medicineName/i);
	});
});

describe("PHI handlers invoke the audit service with the session userId", () => {
	beforeEach(() => {
		prismaMock.__rows.length = 0;
		vi.clearAllMocks();
		prismaMock.user.findUnique.mockResolvedValue({ id: "user-1" });
	});

	it("getUserDoses records a READ audit entry for the session user", async () => {
		const res = makeRes();
		const req = {
			body: {},
			params: { userId: "user-1" },
			user: { id: "user-1" },
			ip: "203.0.113.7",
			headers: { "user-agent": "vitest" },
		} as unknown as Request;

		await OcrRoutes.getUserDoses(req, res);

		expect(res.statusCode).toBe(200);
		expect(prismaMock.auditLog.create).toHaveBeenCalledTimes(1);
		const data = (
			prismaMock.auditLog.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(data.action).toBe("READ");
		expect(data.resourceType).toBe("Dose");
		expect(data.actorUserId).toBe("user-1");
		expect(data.ip).toBe("203.0.113.7");
		expect(data.userAgent).toBe("vitest");
	});
});

describe("audit_log migration SQL (#6)", () => {
	const migrationsDir = path.resolve(__dirname, "../prisma/migrations");

	it("creates the AuditLog table with indexes and a nullable User FK", () => {
		const dir = fs
			.readdirSync(migrationsDir)
			.find((d) => d.endsWith("_audit_log"));
		expect(dir).toBeTruthy();

		const sql = fs.readFileSync(
			path.join(migrationsDir, dir as string, "migration.sql"),
			"utf8",
		);

		expect(sql).toContain('CREATE TABLE "AuditLog"');
		expect(sql).toContain('"AuditLog_actorUserId_idx"');
		expect(sql).toContain('"AuditLog_resourceType_idx"');
		expect(sql).toContain('"AuditLog_createdAt_idx"');
		// Tamper-evidence hash chain columns.
		expect(sql).toContain('"hash"');
		expect(sql).toContain('"prevHash"');
		// FK to User must be ON DELETE SET NULL (audit trail outlives the actor).
		expect(sql).toContain('"AuditLog_actorUserId_fkey"');
		expect(sql).toContain("ON DELETE SET NULL");
		// Append-only: there must be NO updatedAt column on AuditLog.
		expect(sql).not.toMatch(/"updatedAt"/);
	});
});
