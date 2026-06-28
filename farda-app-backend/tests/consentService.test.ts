import * as fs from "node:fs";
import * as path from "node:path";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Tests for the tiered consent capture service (GTM-523).
 *
 * No live DB: `prisma` is mocked with `vi.mock` so the suite is deterministic
 * and CI-friendly, matching the project's existing service tests
 * (provenanceService / auditLog / refillService).
 */

const { prismaMock } = vi.hoisted(() => {
	const consents: Array<Record<string, unknown>> = [];
	let seq = 0;
	const prismaMock = {
		__consents: consents,
		// Audit + provenance ledgers (chained off the latest row).
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
				consents.push(row);
				return row;
			}),
			findFirst: vi.fn(async (args: { where: Record<string, unknown> }) => {
				const where = args.where as { userId: string };
				// Mirror the service: latest row overall (revoked-or-not), newest first.
				const matches = consents
					.filter((c) => c.userId === where.userId)
					.sort(
						(a, b) =>
							(b.grantedAt as Date).getTime() - (a.grantedAt as Date).getTime(),
					);
				return matches[0] ?? null;
			}),
			findMany: vi.fn(async (args: { where: { userId: string } }) =>
				consents
					.filter((c) => c.userId === args.where.userId)
					.sort(
						(a, b) =>
							(b.grantedAt as Date).getTime() - (a.grantedAt as Date).getTime(),
					),
			),
		},
	};
	return { prismaMock };
});

vi.mock("@src/lib/prisma", () => ({ prisma: prismaMock }));

import {
	CONSENT_TIER_RANK,
	type ConsentRecord,
	getConsentHistory,
	getCurrentConsent,
	isConsentTier,
	isPermitted,
	recordConsent,
	revokeConsent,
} from "@src/services/ConsentService";

function reset() {
	prismaMock.__consents.length = 0;
	vi.clearAllMocks();
}

describe("ConsentService.isPermitted — tier ordering", () => {
	const tiers = ["NONE", "CARE_TEAM", "RESEARCH", "COMMERCIAL_AI_TRAINING"] as const;

	it("each tier permits itself and every LOWER use, denies every HIGHER use", () => {
		for (const granted of tiers) {
			const consent = { tier: granted, revokedAt: null } as Pick<
				ConsentRecord,
				"tier" | "revokedAt"
			>;
			for (const required of tiers) {
				const expected =
					CONSENT_TIER_RANK[granted] >= CONSENT_TIER_RANK[required];
				expect(isPermitted(consent, required)).toBe(expected);
			}
		}
	});

	it("COMMERCIAL_AI_TRAINING permits everything; NONE permits only NONE", () => {
		const top = { tier: "COMMERCIAL_AI_TRAINING", revokedAt: null } as const;
		expect(isPermitted(top, "CARE_TEAM")).toBe(true);
		expect(isPermitted(top, "RESEARCH")).toBe(true);
		expect(isPermitted(top, "COMMERCIAL_AI_TRAINING")).toBe(true);

		const none = { tier: "NONE", revokedAt: null } as const;
		expect(isPermitted(none, "NONE")).toBe(true);
		expect(isPermitted(none, "CARE_TEAM")).toBe(false);
	});

	it("a null or revoked consent permits only NONE", () => {
		expect(isPermitted(null, "NONE")).toBe(true);
		expect(isPermitted(null, "CARE_TEAM")).toBe(false);
		const revoked = {
			tier: "COMMERCIAL_AI_TRAINING",
			revokedAt: new Date(),
		} as Pick<ConsentRecord, "tier" | "revokedAt">;
		expect(isPermitted(revoked, "NONE")).toBe(true);
		expect(isPermitted(revoked, "RESEARCH")).toBe(false);
	});

	it("isConsentTier validates untrusted strings", () => {
		expect(isConsentTier("RESEARCH")).toBe(true);
		expect(isConsentTier("research")).toBe(false);
		expect(isConsentTier("WAT")).toBe(false);
		expect(isConsentTier(42)).toBe(false);
	});
});

describe("ConsentService.recordConsent — append + side effects", () => {
	beforeEach(reset);

	it("appends a new row and writes BOTH an AuditLog and a ProvenanceLedgerEntry", async () => {
		await recordConsent({
			userId: "user-1",
			tier: "RESEARCH",
			version: "v1.0",
			scopes: ["research"],
		});

		expect(prismaMock.consent.create).toHaveBeenCalledTimes(1);

		const audit = (
			prismaMock.auditLog.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(audit.action).toBe("CREATE");
		expect(audit.resourceType).toBe("Consent");
		expect((audit.metadata as Record<string, unknown>).tier).toBe("RESEARCH");
		expect((audit.metadata as Record<string, unknown>).version).toBe("v1.0");

		const prov = (
			prismaMock.provenanceLedgerEntry.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(prov.resourceType).toBe("Consent");
		expect((prov.metadata as Record<string, unknown>).tier).toBe("RESEARCH");
	});

	it("never mutates an existing row — history APPENDS", async () => {
		await recordConsent({ userId: "user-1", tier: "CARE_TEAM", version: "v1" });
		await recordConsent({ userId: "user-1", tier: "RESEARCH", version: "v1" });
		const history = await getConsentHistory("user-1");
		expect(history.length).toBe(2);
		// Newest first.
		expect(history[0].tier).toBe("RESEARCH");
		expect(history[1].tier).toBe("CARE_TEAM");
	});

	it("does NOT leak PHI into the audit/provenance metadata", async () => {
		await recordConsent({
			userId: "user-1",
			tier: "RESEARCH",
			version: "v1",
			purpose: "Oncology study",
		});
		const audit = JSON.stringify(
			(prismaMock.auditLog.create.mock.calls[0][0] as { data: unknown }).data,
		);
		expect(audit).not.toMatch(/mood|note|medication|email|phone/i);
	});
});

describe("ConsentService.getCurrentConsent — latest non-revoked", () => {
	beforeEach(reset);

	it("returns the latest non-revoked row by grantedAt", async () => {
		await recordConsent({ userId: "user-1", tier: "CARE_TEAM", version: "v1" });
		await recordConsent({ userId: "user-1", tier: "RESEARCH", version: "v2" });
		const current = await getCurrentConsent("user-1");
		expect(current?.tier).toBe("RESEARCH");
		expect(current?.version).toBe("v2");
	});

	it("returns null when the user has never consented", async () => {
		expect(await getCurrentConsent("nobody")).toBeNull();
	});

	it("revocation appends a revoked row and clears current consent", async () => {
		await recordConsent({
			userId: "user-1",
			tier: "COMMERCIAL_AI_TRAINING",
			version: "v3",
		});
		expect((await getCurrentConsent("user-1"))?.tier).toBe(
			"COMMERCIAL_AI_TRAINING",
		);

		const revoked = await revokeConsent("user-1");
		expect(revoked?.revokedAt).toBeInstanceOf(Date);
		// Append-only: the revoked row is a NEW row.
		expect((await getConsentHistory("user-1")).length).toBe(2);
		// No active consent now.
		expect(await getCurrentConsent("user-1")).toBeNull();
	});

	it("revocation writes an audit + provenance entry; returns null with nothing to revoke", async () => {
		expect(await revokeConsent("nobody")).toBeNull();
		expect(prismaMock.consent.create).not.toHaveBeenCalled();

		await recordConsent({ userId: "user-1", tier: "RESEARCH", version: "v1" });
		vi.clearAllMocks();
		await revokeConsent("user-1");
		const audit = (
			prismaMock.auditLog.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect(audit.action).toBe("DELETE");
		expect(prismaMock.provenanceLedgerEntry.create).toHaveBeenCalledTimes(1);
	});
});

describe("consent_capture migration SQL (GTM-523)", () => {
	const migrationsDir = path.resolve(__dirname, "../prisma/migrations");

	function migrationSql(): string {
		const dir = fs
			.readdirSync(migrationsDir)
			.find((d) => d.endsWith("_consent_capture"));
		expect(dir).toBeTruthy();
		return fs.readFileSync(
			path.join(migrationsDir, dir as string, "migration.sql"),
			"utf8",
		);
	}

	it("creates the Consent table idempotently with a guarded enum", () => {
		const sql = migrationSql();
		expect(sql).toContain('CREATE TABLE IF NOT EXISTS "Consent"');
		// Enum is created guarded (idempotent re-apply).
		expect(sql).toMatch(/pg_type WHERE typname = 'ConsentTier'/);
		expect(sql).toContain(
			"CREATE TYPE \"ConsentTier\" AS ENUM ('NONE', 'CARE_TEAM', 'RESEARCH', 'COMMERCIAL_AI_TRAINING')",
		);
	});

	it("has the tier/version/scopes/grantedAt/revokedAt columns", () => {
		const sql = migrationSql();
		for (const col of [
			'"tier"',
			'"version"',
			'"scopes"',
			'"purpose"',
			'"grantedAt"',
			'"revokedAt"',
		]) {
			expect(sql).toContain(col);
		}
	});

	it("FK to User is ON DELETE CASCADE and indexes are guarded", () => {
		const sql = migrationSql();
		expect(sql).toContain('"Consent_userId_fkey"');
		expect(sql).toContain("ON DELETE CASCADE");
		expect(sql).toContain(
			'CREATE INDEX IF NOT EXISTS "Consent_userId_grantedAt_idx"',
		);
	});
});
