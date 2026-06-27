import * as fs from "node:fs";
import * as path from "node:path";
import type { Request, Response } from "express";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Persistence tests for the multi-medicine + multi-prescription data model
 * (GTM-511, issues #12 / #13).
 *
 * No live DB: `prisma` is mocked with `vi.mock` so the suite is deterministic
 * and CI-friendly (no Postgres / credentials).
 */

const { prismaMock } = vi.hoisted(() => {
	const prescriptions: Array<{ id: string; userId: string }> = [];
	let seq = 0;
	const prismaMock = {
		__prescriptions: prescriptions,
		user: {
			findUnique: vi.fn(async () => ({ id: "user-1" })),
		},
		prescription: {
			// CREATE a fresh prescription on each call (no upsert / overwrite).
			create: vi.fn(async (args: { data: { userId: string } }) => {
				seq += 1;
				const row = { id: `rx-${seq}`, userId: args.data.userId };
				prescriptions.push(row);
				return { ...row, medicines: [] };
			}),
			findMany: vi.fn(async () => prescriptions),
		},
		medicine: {
			create: vi.fn(async () => ({})),
			createMany: vi.fn(async () => ({ count: 0 })),
		},
		dose: {
			deleteMany: vi.fn(async () => ({ count: 0 })),
			createMany: vi.fn(async () => ({ count: 0 })),
			findMany: vi.fn(async () => []),
		},
	};
	return { prismaMock };
});

vi.mock("@src/lib/prisma", () => ({ prisma: prismaMock }));

import OcrRoutes from "@src/routes/OcrRoutes";

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

function makeReq(body: unknown, userId = "user-1"): Request {
	return {
		body,
		params: {},
		user: { id: userId },
	} as unknown as Request;
}

const threeMeds = {
	medicines_names: [
		{ medicine_name: "Lisinopril", instructions: "Take one daily" },
		{ medicine_name: "Metformin", instructions: "Take twice daily" },
		{ medicine_name: "Atorvastatin", instructions: "Take at night" },
	],
	doses_per_day: 1,
	duration_days: 1,
};

describe("savePrescription multi-medicine persistence (#13)", () => {
	beforeEach(() => {
		prismaMock.__prescriptions.length = 0;
		vi.clearAllMocks();
		prismaMock.user.findUnique.mockResolvedValue({ id: "user-1" });
	});

	it("persists ALL medicines (not just [0])", async () => {
		const res = makeRes();
		await OcrRoutes.savePrescription(makeReq(threeMeds), res);

		expect(res.statusCode).toBe(200);
		expect(prismaMock.prescription.create).toHaveBeenCalledTimes(1);

		// The full medication list is written via the nested create on the
		// prescription.
		const createArg = prismaMock.prescription.create.mock.calls[0][0] as {
			data: { medicines: { create: Array<{ medicineName: string }> } };
		};
		const meds = createArg.data.medicines.create;
		expect(meds.length).toBe(3);
		expect(meds.length).toBeGreaterThan(1);
		expect(meds.map((m) => m.medicineName)).toEqual([
			"Lisinopril",
			"Metformin",
			"Atorvastatin",
		]);
	});

	it("creates a SECOND prescription on a second save (no overwrite)", async () => {
		await OcrRoutes.savePrescription(makeReq(threeMeds), makeRes());
		await OcrRoutes.savePrescription(makeReq(threeMeds), makeRes());

		expect(prismaMock.prescription.create).toHaveBeenCalledTimes(2);
		expect(prismaMock.__prescriptions.length).toBe(2);
		// Distinct prescription ids — the first was not replaced.
		expect(prismaMock.__prescriptions[0].id).not.toBe(
			prismaMock.__prescriptions[1].id,
		);
	});

	it("derives userId from the session, not the client body", async () => {
		const res = makeRes();
		await OcrRoutes.savePrescription(
			makeReq({ ...threeMeds, userId: "attacker-999" }, "user-1"),
			res,
		);
		expect(res.statusCode).toBe(200);
		const createArg = prismaMock.prescription.create.mock.calls[0][0] as {
			data: { userId: string };
		};
		expect(createArg.data.userId).toBe("user-1");
	});
});

describe("getUserPrescriptions returns a list (#13)", () => {
	beforeEach(() => {
		prismaMock.__prescriptions.length = 0;
		vi.clearAllMocks();
	});

	it("uses findMany and returns all the user's prescriptions", async () => {
		prismaMock.prescription.findMany.mockResolvedValueOnce([
			{ id: "rx-1", userId: "user-1", medicines: [] },
			{ id: "rx-2", userId: "user-1", medicines: [] },
		]);
		const res = makeRes();
		const req = {
			body: {},
			params: { userId: "user-1" },
			user: { id: "user-1" },
		} as unknown as Request;

		await OcrRoutes.getUserPrescriptions(req, res);

		expect(prismaMock.prescription.findMany).toHaveBeenCalledTimes(1);
		expect(Array.isArray(res.body)).toBe(true);
		expect((res.body as unknown[]).length).toBe(2);
	});
});

describe("multi_med_and_dose migration SQL (#12 / #13)", () => {
	const migrationsDir = path.resolve(__dirname, "../prisma/migrations");

	it("creates Dose + Medicine tables and drops the unique userId index", () => {
		const dir = fs
			.readdirSync(migrationsDir)
			.find((d) => d.endsWith("_multi_med_and_dose"));
		expect(dir).toBeTruthy();

		const sql = fs.readFileSync(
			path.join(migrationsDir, dir as string, "migration.sql"),
			"utf8",
		);

		expect(sql).toContain('CREATE TABLE "Medicine"');
		expect(sql).toMatch(/CREATE TABLE (IF NOT EXISTS )?"Dose"/);
		expect(sql).toContain('DROP INDEX IF EXISTS "Prescription_userId_key"');
		expect(sql).toContain("CREATE INDEX");
		// FK constraints wired up.
		expect(sql).toContain('"Medicine_prescriptionId_fkey"');
		expect(sql).toContain('"Dose_prescriptionId_fkey"');
	});
});
