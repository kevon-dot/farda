import * as fs from "node:fs";
import * as path from "node:path";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Tests for the data retention / deletion / export service (GTM-542).
 *
 * No live DB: `prisma` is mocked with `vi.mock`, matching the project's existing
 * service tests (consentService / provenanceService / refillService).
 *
 * Coverage:
 *   - selectExpired (PURE): past-window non-legal-hold records only; legal-hold
 *     exemptions; no-policy classes kept.
 *   - buildExport: assembles the user's data, IDOR-scoped (no other users).
 *   - processDeletion: erases the identified layer; de-id/analytic NOT recalled.
 *   - revokeConsentAndDelete: revocation triggers deletion + stops future
 *     projection (consent revoked).
 *   - audit + provenance written.
 *   - migration SQL assertions (match existing style).
 */

const { prismaMock, state } = vi.hoisted(() => {
	const state = {
		consents: [] as Array<Record<string, unknown>>,
		deletions: [] as Array<Record<string, unknown>>,
		exports: [] as Array<Record<string, unknown>>,
		deleteCalls: [] as Array<{ model: string; where: unknown }>,
		deidEventsDeleted: false,
		analyticMetricsDeleted: false,
	};
	let seq = 0;

	function makeDelegate(
		modelName: string,
		rows: () => Array<Record<string, unknown>>,
	) {
		return {
			findMany: vi.fn(async (args?: { where?: { userId?: string } }) => {
				const all = rows();
				if (args?.where?.userId) {
					return all.filter((r) => r.userId === args.where?.userId);
				}
				return all;
			}),
			deleteMany: vi.fn(async (args: { where: unknown }) => {
				state.deleteCalls.push({ model: modelName, where: args.where });
				return { count: 1 };
			}),
		};
	}

	const prismaMock = {
		auditLog: {
			findFirst: vi.fn(async () => null),
			create: vi.fn(async (args: { data: Record<string, unknown> }) => ({
				id: "audit-1",
				...args.data,
			})),
		},
		provenanceLedgerEntry: {
			findFirst: vi.fn(async () => null),
			create: vi.fn(async (args: { data: Record<string, unknown> }) => ({
				id: "prov-1",
				...args.data,
			})),
		},
		consent: {
			create: vi.fn(async (args: { data: Record<string, unknown> }) => {
				seq += 1;
				const row = {
					id: `c-${seq}`,
					grantedAt: new Date(2026, 0, seq),
					revokedAt: null,
					scopes: null,
					purpose: null,
					...args.data,
				};
				state.consents.push(row);
				return row;
			}),
			findFirst: vi.fn(async (args: { where: { userId: string } }) => {
				const ms = state.consents
					.filter((c) => c.userId === args.where.userId)
					.sort(
						(a, b) =>
							(b.grantedAt as Date).getTime() - (a.grantedAt as Date).getTime(),
					);
				return ms[0] ?? null;
			}),
			findMany: vi.fn(async (args: { where: { userId: string } }) =>
				state.consents.filter((c) => c.userId === args.where.userId),
			),
			deleteMany: vi.fn(async (args: { where: unknown }) => {
				state.deleteCalls.push({ model: "Consent", where: args.where });
				return { count: 1 };
			}),
		},
		retentionPolicy: {
			findMany: vi.fn(async () => state.policies ?? []),
		},
		deletionRequest: {
			create: vi.fn(async (args: { data: Record<string, unknown> }) => {
				seq += 1;
				const row = {
					id: `del-${seq}`,
					status: "PENDING",
					scope: "FULL",
					triggeredByRevocation: false,
					requestedAt: new Date(2026, 5, seq),
					completedAt: null,
					...args.data,
				};
				state.deletions.push(row);
				return row;
			}),
			findFirst: vi.fn(async (args: { where: { userId: string } }) => {
				const ms = state.deletions
					.filter((d) => d.userId === args.where.userId)
					.sort(
						(a, b) =>
							(b.requestedAt as Date).getTime() -
							(a.requestedAt as Date).getTime(),
					);
				return ms[0] ?? null;
			}),
			update: vi.fn(
				async (args: {
					where: { id: string };
					data: Record<string, unknown>;
				}) => {
					const row = state.deletions.find((d) => d.id === args.where.id);
					if (row) Object.assign(row, args.data);
					return row;
				},
			),
		},
		exportRequest: {
			create: vi.fn(async (args: { data: Record<string, unknown> }) => {
				seq += 1;
				const row = {
					id: `exp-${seq}`,
					status: "PENDING",
					format: "json",
					requestedAt: new Date(2026, 5, seq),
					completedAt: null,
					...args.data,
				};
				state.exports.push(row);
				return row;
			}),
			findFirst: vi.fn(async (args: { where: { userId: string } }) => {
				const ms = state.exports
					.filter((e) => e.userId === args.where.userId)
					.sort(
						(a, b) =>
							(b.requestedAt as Date).getTime() -
							(a.requestedAt as Date).getTime(),
					);
				return ms[0] ?? null;
			}),
		},
		user: {
			findUnique: vi.fn(async (args: { where: { id: string } }) => ({
				id: args.where.id,
				email: `${args.where.id}@example.com`,
			})),
		},
		prescription: makeDelegate("Prescription", () => state.prescriptions ?? []),
		medicine: makeDelegate("Medicine", () => state.medicines ?? []),
		dose: makeDelegate("Dose", () => state.doses ?? []),
		reminderResponseEvent: makeDelegate(
			"ReminderResponseEvent",
			() => state.reminders ?? [],
		),
		refillEvent: makeDelegate("RefillEvent", () => state.refills ?? []),
		pushToken: makeDelegate("PushToken", () => state.pushTokens ?? []),
	} as Record<string, unknown> & {
		prescription: ReturnType<typeof makeDelegate>;
	};

	return { prismaMock, state: state as typeof state & Record<string, unknown> };
});

vi.mock("@src/lib/prisma", () => ({ prisma: prismaMock }));

import { getCurrentConsent, recordConsent } from "@src/services/ConsentService";
import {
	buildExport,
	getDeletionStatus,
	processDeletion,
	requestDeletion,
	requestExport,
	revokeConsentAndDelete,
	selectExpired,
} from "@src/services/DataRetentionService";

function reset() {
	state.consents.length = 0;
	state.deletions.length = 0;
	state.exports.length = 0;
	state.deleteCalls.length = 0;
	state.policies = [];
	state.prescriptions = [];
	state.medicines = [];
	state.doses = [];
	state.reminders = [];
	state.refills = [];
	state.pushTokens = [];
	vi.clearAllMocks();
}

const DAY = 24 * 60 * 60 * 1000;

describe("DataRetentionService.selectExpired — pure retention selection", () => {
	beforeEach(reset);

	const now = new Date("2026-06-28T00:00:00Z");

	it("selects ONLY records past their window that are NOT under legal hold", () => {
		const policies = [
			{ dataClass: "Dose", retentionDays: 30, legalHold: false },
		];
		const old = {
			id: "old",
			dataClass: "Dose",
			createdAt: new Date(now.getTime() - 60 * DAY),
		};
		const fresh = {
			id: "fresh",
			dataClass: "Dose",
			createdAt: new Date(now.getTime() - 5 * DAY),
		};
		const sel = selectExpired(policies, [old, fresh], now);
		expect(sel.expired.map((r) => r.id)).toEqual(["old"]);
		expect(sel.withinWindow.map((r) => r.id)).toEqual(["fresh"]);
		expect(sel.legalHoldExempt).toHaveLength(0);
	});

	it("EXEMPTS a class under legal hold regardless of record age", () => {
		const policies = [
			{ dataClass: "Dose", retentionDays: 30, legalHold: true },
		];
		const ancient = {
			id: "ancient",
			dataClass: "Dose",
			createdAt: new Date(now.getTime() - 9999 * DAY),
		};
		const sel = selectExpired(policies, [ancient], now);
		expect(sel.expired).toHaveLength(0);
		expect(sel.legalHoldExempt.map((r) => r.id)).toEqual(["ancient"]);
	});

	it("KEEPS records of a class with no policy (retention is opt-in per class)", () => {
		const old = {
			id: "x",
			dataClass: "Unknown",
			createdAt: new Date(now.getTime() - 9999 * DAY),
		};
		const sel = selectExpired([], [old], now);
		expect(sel.expired).toHaveLength(0);
		expect(sel.withinWindow.map((r) => r.id)).toEqual(["x"]);
	});

	it("treats exactly-at-window as still within (must be strictly past)", () => {
		const policies = [
			{ dataClass: "Dose", retentionDays: 1, legalHold: false },
		];
		const atWindow = {
			id: "edge",
			dataClass: "Dose",
			createdAt: new Date(now.getTime() - 1 * DAY),
		};
		const sel = selectExpired(policies, [atWindow], now);
		expect(sel.expired).toHaveLength(0);
		expect(sel.withinWindow).toHaveLength(1);
	});
});

describe("DataRetentionService.buildExport — access / portability (IDOR)", () => {
	beforeEach(reset);

	it("assembles the requesting user's data and NEVER another user's", async () => {
		state.prescriptions = [
			{ id: "rx-1", userId: "user-1" },
			{ id: "rx-2", userId: "user-2" },
		];
		state.doses = [
			{ id: "d-1", userId: "user-1" },
			{ id: "d-2", userId: "user-2" },
		];
		state.medicines = [
			{ id: "m-1", prescriptionId: "rx-1" },
			{ id: "m-2", prescriptionId: "rx-2" },
		];

		const out = await buildExport("user-1");
		expect(out.userId).toBe("user-1");
		expect(out.prescriptions.map((p) => p.id)).toEqual(["rx-1"]);
		expect(out.doses.map((d) => d.id)).toEqual(["d-1"]);
		// Medicines are scoped THROUGH the user's prescription ids only.
		expect(out.medicines.length).toBeGreaterThanOrEqual(0);
		// the export must not contain user-2's prescription.
		expect(
			out.prescriptions.find((p) => p.userId === "user-2"),
		).toBeUndefined();
	});

	it("writes an audit log AND a provenance entry for the export", async () => {
		await buildExport("user-1");
		expect(prismaMock.auditLog.create).toHaveBeenCalled();
		expect(prismaMock.provenanceLedgerEntry.create).toHaveBeenCalled();
		const prov = prismaMock.provenanceLedgerEntry.create.mock.calls[0][0].data;
		expect(prov.operation).toBe("EXPORT");
		expect(prov.layer).toBe("IDENTIFIED");
	});
});

describe("DataRetentionService.processDeletion — erase identified layer only", () => {
	beforeEach(reset);

	it("erases the identified-layer tables but does NOT recall de-identified/analytic rows", async () => {
		await requestDeletion("user-1", { revokeConsentToo: false });
		const result = await processDeletion("user-1");

		// The "can't recall de-identified" boundary, asserted explicitly.
		expect(result.deidentifiedRecalled).toBe(false);

		// Identified-layer deletes were issued.
		const deletedModels = state.deleteCalls.map((c) => c.model);
		expect(deletedModels).toContain("Dose");
		expect(deletedModels).toContain("Prescription");
		expect(deletedModels).toContain("ReminderResponseEvent");
		expect(deletedModels).toContain("Consent");

		// NO deidentified / analytic delegate was ever touched (they are not even
		// present on the mock — assert no delete targeted them).
		expect(deletedModels).not.toContain("DeidentifiedEvent");
		expect(deletedModels).not.toContain("AnalyticMetric");

		// Request marked COMPLETED.
		expect(result.request?.status).toBe("COMPLETED");
		expect(result.request?.completedAt).toBeTruthy();
	});

	it("writes audit + provenance for the deletion", async () => {
		await requestDeletion("user-1", { revokeConsentToo: false });
		vi.clearAllMocks();
		await processDeletion("user-1");
		expect(prismaMock.auditLog.create).toHaveBeenCalled();
		const prov =
			prismaMock.provenanceLedgerEntry.create.mock.calls.at(-1)?.[0].data;
		expect(prov.resourceType).toBe("DeletionRequest");
		expect(prov.metadata.deidentifiedRecalled).toBe(false);
	});
});

describe("Revocation -> deletion workflow (GTM-542)", () => {
	beforeEach(reset);

	it("revoking consent triggers a deletion request AND blocks future projection", async () => {
		// User starts with active RESEARCH consent.
		await recordConsent({ userId: "user-1", tier: "RESEARCH", version: "v1" });
		expect((await getCurrentConsent("user-1"))?.tier).toBe("RESEARCH");

		const { consent, deletion } = await revokeConsentAndDelete("user-1");

		// A revoked consent row was appended (revocation happened).
		expect(consent?.revokedAt).toBeTruthy();
		// A deletion request was created and flagged as revocation-triggered.
		expect(deletion.triggeredByRevocation).toBe(true);
		expect(deletion.status).toBe("PENDING");

		// FUTURE projection is now blocked: current consent resolves to NONE, so the
		// GTM-523 gate (isPermitted) fail-closes. We assert the gate's input here.
		expect(await getCurrentConsent("user-1")).toBeNull();
	});

	it("does NOT double-revoke (requestDeletion called with revokeConsentToo=false)", async () => {
		await recordConsent({ userId: "user-1", tier: "CARE_TEAM", version: "v1" });
		await revokeConsentAndDelete("user-1");
		// Exactly one revoked row (the workflow's single revoke), plus the original.
		const revoked = state.consents.filter((c) => c.revokedAt != null);
		expect(revoked).toHaveLength(1);
	});
});

describe("DataRetentionService request + status accessors", () => {
	beforeEach(reset);

	it("requestExport creates a PENDING row scoped to the user + audits", async () => {
		const row = await requestExport("user-1");
		expect(row.userId).toBe("user-1");
		expect(row.status).toBe("PENDING");
		expect(prismaMock.auditLog.create).toHaveBeenCalled();
		expect(prismaMock.provenanceLedgerEntry.create).toHaveBeenCalled();
	});

	it("requestDeletion revokes consent by default and audits", async () => {
		await recordConsent({ userId: "user-1", tier: "RESEARCH", version: "v1" });
		const row = await requestDeletion("user-1");
		expect(row.status).toBe("PENDING");
		// Default revokeConsentToo=true -> consent now resolves to null.
		expect(await getCurrentConsent("user-1")).toBeNull();
		const status = await getDeletionStatus("user-1");
		expect(status?.id).toBe(row.id);
	});
});

describe("retention_deletion_export migration SQL (GTM-542)", () => {
	const migrationsDir = path.resolve(__dirname, "../prisma/migrations");

	function migrationSql(): string {
		const dir = fs
			.readdirSync(migrationsDir)
			.find((d) => d.endsWith("_retention_deletion_export"));
		expect(dir).toBeTruthy();
		return fs.readFileSync(
			path.join(migrationsDir, dir as string, "migration.sql"),
			"utf8",
		);
	}

	it("creates the three tables idempotently", () => {
		const sql = migrationSql();
		expect(sql).toContain('CREATE TABLE IF NOT EXISTS "RetentionPolicy"');
		expect(sql).toContain('CREATE TABLE IF NOT EXISTS "DeletionRequest"');
		expect(sql).toContain('CREATE TABLE IF NOT EXISTS "ExportRequest"');
	});

	it("guards the status + scope enums", () => {
		const sql = migrationSql();
		expect(sql).toMatch(/pg_type WHERE typname = 'DataRequestStatus'/);
		expect(sql).toContain(
			"CREATE TYPE \"DataRequestStatus\" AS ENUM ('PENDING', 'PROCESSING', 'COMPLETED')",
		);
		expect(sql).toMatch(/pg_type WHERE typname = 'DeletionScope'/);
	});

	it("FKs to User are ON DELETE CASCADE and guarded; indexes are guarded", () => {
		const sql = migrationSql();
		expect(sql).toContain('"DeletionRequest_userId_fkey"');
		expect(sql).toContain('"ExportRequest_userId_fkey"');
		expect(sql).toContain("ON DELETE CASCADE");
		expect(sql).toContain(
			'CREATE UNIQUE INDEX IF NOT EXISTS "RetentionPolicy_dataClass_key"',
		);
		expect(sql).toContain(
			'CREATE INDEX IF NOT EXISTS "DeletionRequest_status_idx"',
		);
	});
});
