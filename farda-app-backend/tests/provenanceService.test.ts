import * as fs from "node:fs";
import * as path from "node:path";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Tests for the provenance ledger (GTM-522).
 *
 * No live DB: `prisma` is mocked with `vi.mock` so the suite is deterministic
 * and CI-friendly, mirroring the auditLog.test.ts hash-chain tests.
 */

const { prismaMock } = vi.hoisted(() => {
	const rows: Array<Record<string, unknown>> = [];
	const prismaMock = {
		__rows: rows,
		provenanceLedgerEntry: {
			findFirst: vi.fn(async () =>
				rows.length ? rows[rows.length - 1] : null,
			),
			create: vi.fn(async (args: { data: Record<string, unknown> }) => {
				const row = { id: `prov-${rows.length + 1}`, ...args.data };
				rows.push(row);
				return row;
			}),
			findMany: vi.fn(async () => rows),
		},
	};
	return { prismaMock };
});

vi.mock("@src/lib/prisma", () => ({ prisma: prismaMock }));

import {
	type LedgerRow,
	recordProvenance,
	verifyChain,
} from "@src/services/ProvenanceService";

/** Build a LedgerRow from a persisted create() data payload. */
function toLedgerRow(data: Record<string, unknown>): LedgerRow {
	return {
		actorUserId: (data.actorUserId as string | null) ?? null,
		operation: data.operation as string,
		layer: data.layer as string,
		sourceLayer: (data.sourceLayer as string | null) ?? null,
		resourceType: data.resourceType as string,
		resourceId: (data.resourceId as string | null) ?? null,
		ip: (data.ip as string | null) ?? null,
		userAgent: (data.userAgent as string | null) ?? null,
		metadata: (data.metadata as Record<string, unknown> | null) ?? null,
		prevHash: (data.prevHash as string | null) ?? null,
		hash: data.hash as string,
	};
}

function persistedRows(): LedgerRow[] {
	return prismaMock.provenanceLedgerEntry.create.mock.calls.map((c) =>
		toLedgerRow((c[0] as { data: Record<string, unknown> }).data),
	);
}

describe("recordProvenance — append-only hash chain", () => {
	beforeEach(() => {
		prismaMock.__rows.length = 0;
		vi.clearAllMocks();
	});

	it("first row has a null prevHash and a non-empty hash", async () => {
		await recordProvenance({
			operation: "TRANSFORM",
			layer: "DEIDENTIFIED",
			sourceLayer: "IDENTIFIED",
			resourceType: "DeidentifiedSubject",
			resourceId: "pseudo-1",
		});
		const data = (
			prismaMock.provenanceLedgerEntry.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(data.prevHash).toBeNull();
		expect(typeof data.hash).toBe("string");
		expect((data.hash as string).length).toBeGreaterThan(0);
	});

	it("chains each new hash off the previous row's hash", async () => {
		await recordProvenance({
			operation: "TRANSFORM",
			layer: "DEIDENTIFIED",
			sourceLayer: "IDENTIFIED",
			resourceType: "DeidentifiedSubject",
			resourceId: "pseudo-1",
		});
		await recordProvenance({
			operation: "EXPORT",
			layer: "ANALYTIC",
			resourceType: "AnalyticMetric",
			resourceId: "m-1",
		});
		const rows = persistedRows();
		expect(rows[1].prevHash).toBe(rows[0].hash);
		expect(rows[1].hash).not.toBe(rows[0].hash);
	});

	it("produces a chain that verifyChain accepts as valid", async () => {
		await recordProvenance({
			operation: "CREATE",
			layer: "IDENTIFIED",
			resourceType: "Dose",
			resourceId: "dose-1",
		});
		await recordProvenance({
			operation: "TRANSFORM",
			layer: "DEIDENTIFIED",
			sourceLayer: "IDENTIFIED",
			resourceType: "DeidentifiedEvent",
			resourceId: "pseudo-1",
		});
		const result = verifyChain(persistedRows());
		expect(result.valid).toBe(true);
		expect(result.brokenAtIndex).toBeNull();
		expect(result.checked).toBe(2);
	});

	it("does NOT throw when the insert fails (fail-open)", async () => {
		prismaMock.provenanceLedgerEntry.create.mockRejectedValueOnce(
			new Error("db down"),
		);
		await expect(
			recordProvenance({
				operation: "ACCESS",
				layer: "ANALYTIC",
				resourceType: "AnalyticMetric",
			}),
		).resolves.toBeUndefined();
	});

	it("records NO PHI — only layer/operation/ids/metadata keys", async () => {
		await recordProvenance({
			operation: "TRANSFORM",
			layer: "DEIDENTIFIED",
			sourceLayer: "IDENTIFIED",
			resourceType: "DeidentifiedEvent",
			resourceId: "pseudo-1",
			metadata: { count: 3 },
		});
		const data = (
			prismaMock.provenanceLedgerEntry.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(Object.keys(data).sort()).toEqual(
			[
				"actorUserId",
				"hash",
				"ip",
				"layer",
				"metadata",
				"operation",
				"prevHash",
				"resourceId",
				"resourceType",
				"sourceLayer",
				"userAgent",
			].sort(),
		);
		const serialized = JSON.stringify(data);
		expect(serialized).not.toMatch(/mood|note|medication|medicineName|email/i);
	});
});

describe("verifyChain — tamper detection", () => {
	beforeEach(() => {
		prismaMock.__rows.length = 0;
		vi.clearAllMocks();
	});

	async function buildThreeRowChain(): Promise<LedgerRow[]> {
		await recordProvenance({
			operation: "CREATE",
			layer: "IDENTIFIED",
			resourceType: "Dose",
			resourceId: "dose-1",
		});
		await recordProvenance({
			operation: "TRANSFORM",
			layer: "DEIDENTIFIED",
			sourceLayer: "IDENTIFIED",
			resourceType: "DeidentifiedEvent",
			resourceId: "pseudo-1",
		});
		await recordProvenance({
			operation: "EXPORT",
			layer: "ANALYTIC",
			resourceType: "AnalyticMetric",
			resourceId: "m-1",
		});
		return persistedRows();
	}

	it("detects a mutated field (content no longer matches the hash)", async () => {
		const rows = await buildThreeRowChain();
		// Tamper: change the middle row's resourceId WITHOUT recomputing its hash.
		rows[1] = { ...rows[1], resourceId: "pseudo-TAMPERED" };
		const result = verifyChain(rows);
		expect(result.valid).toBe(false);
		expect(result.brokenAtIndex).toBe(1);
	});

	it("detects a removed row (broken chain linkage)", async () => {
		const rows = await buildThreeRowChain();
		// Drop the middle row: row[2].prevHash no longer matches row[0].hash.
		const tampered = [rows[0], rows[2]];
		const result = verifyChain(tampered);
		expect(result.valid).toBe(false);
		expect(result.brokenAtIndex).toBe(1);
	});

	it("accepts an untampered chain", async () => {
		const rows = await buildThreeRowChain();
		expect(verifyChain(rows).valid).toBe(true);
	});
});

describe("data_layers_provenance migration SQL (GTM-522)", () => {
	const migrationsDir = path.resolve(__dirname, "../prisma/migrations");

	function migrationSql(): string {
		const dir = fs
			.readdirSync(migrationsDir)
			.find((d) => d.endsWith("_data_layers_provenance"));
		expect(dir).toBeTruthy();
		return fs.readFileSync(
			path.join(migrationsDir, dir as string, "migration.sql"),
			"utf8",
		);
	}

	it("creates the de-identified, analytic and provenance tables (idempotent)", () => {
		const sql = migrationSql();
		expect(sql).toContain('CREATE TABLE IF NOT EXISTS "DeidentifiedSubject"');
		expect(sql).toContain('CREATE TABLE IF NOT EXISTS "DeidentifiedEvent"');
		expect(sql).toContain('CREATE TABLE IF NOT EXISTS "AnalyticMetric"');
		expect(sql).toContain('CREATE TABLE IF NOT EXISTS "ProvenanceLedgerEntry"');
	});

	it("provenance ledger has hash-chain columns and is append-only (no updatedAt)", () => {
		const sql = migrationSql();
		// Isolate the ProvenanceLedgerEntry CREATE TABLE block.
		const start = sql.indexOf('"ProvenanceLedgerEntry" (');
		const block = sql.slice(start, sql.indexOf(");", start));
		expect(block).toContain('"hash"');
		expect(block).toContain('"prevHash"');
		// Append-only: NO updatedAt on the ledger.
		expect(block).not.toMatch(/"updatedAt"/);
	});

	it("provenance FK to User is ON DELETE SET NULL (ledger outlives the actor)", () => {
		const sql = migrationSql();
		expect(sql).toContain('"ProvenanceLedgerEntry_actorUserId_fkey"');
		expect(sql).toContain("ON DELETE SET NULL");
	});

	it("de-identified subject has NO foreign key back to User (no re-id path)", () => {
		const sql = migrationSql();
		// There must be no FK constraint from the de-id layer to the identified
		// User table (no DeidentifiedSubject -> User foreign key of any name).
		expect(sql).not.toMatch(/DeidentifiedSubject_\w*[Uu]ser\w*_fkey/);
		expect(sql).not.toMatch(/DeidentifiedSubject\b[^;]*REFERENCES "User"/);
	});

	it("pseudonym + analytic uniqueness indexes exist (idempotent upserts)", () => {
		const sql = migrationSql();
		expect(sql).toContain('"DeidentifiedSubject_subjectKey_key"');
		expect(sql).toContain('"AnalyticMetric_metric_cohort_period_key"');
	});
});
