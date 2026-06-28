import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Pipeline-integration tests for tiered consent enforcement (GTM-523).
 *
 * Verifies that the DataPipelineService gates cross-layer projection on the
 * user's CURRENT consent (ConsentService) and stamps the consent tier+version
 * onto the provenance entry ("consent state on every record"). No live DB:
 * `prisma` is mocked.
 */

const { prismaMock, state } = vi.hoisted(() => {
	// The de-identification transform reads env.DEID_SALT, which is captured at
	// module-load. Set it inside the hoisted block so it is present BEFORE env.ts
	// (transitively imported by DataPipelineService) is evaluated.
	process.env.DEID_SALT = "test-salt-123";
	const state: { current: Record<string, unknown> | null } = { current: null };
	const prismaMock = {
		__state: state,
		consent: {
			findFirst: vi.fn(async () => state.current),
			findMany: vi.fn(async () => (state.current ? [state.current] : [])),
			create: vi.fn(async (args: { data: Record<string, unknown> }) => ({
				id: "c-1",
				...args.data,
			})),
		},
		auditLog: {
			findFirst: vi.fn(async () => null),
			create: vi.fn(async (args: { data: Record<string, unknown> }) => ({
				id: "a-1",
				...args.data,
			})),
		},
		provenanceLedgerEntry: {
			findFirst: vi.fn(async () => null),
			create: vi.fn(async (args: { data: Record<string, unknown> }) => ({
				id: "p-1",
				...args.data,
			})),
		},
		deidentifiedSubject: {
			upsert: vi.fn(async () => ({ id: "subj-1" })),
			findUnique: vi.fn(async () => ({ id: "subj-1" })),
		},
		deidentifiedEvent: {
			create: vi.fn(async (args: { data: Record<string, unknown> }) => ({
				id: "ev-1",
				...args.data,
			})),
		},
		analyticMetric: {
			upsert: vi.fn(async (args: { create: Record<string, unknown> }) => ({
				id: "m-1",
				...args.create,
			})),
		},
	};
	return { prismaMock, state };
});

vi.mock("@src/lib/prisma", () => ({ prisma: prismaMock }));

import {
	ConsentNotPermittedError,
	projectSubject,
	upsertAnalyticMetric,
} from "@src/services/DataPipelineService";

function setConsent(tier: string | null, version = "v1") {
	state.current = tier
		? { id: "c-1", userId: "user-1", tier, version, revokedAt: null }
		: null;
}

const RECORD = { userId: "user-1", name: "x", region: "CA", age: 40 };

describe("DataPipeline consent gate — de-identified layer", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		state.current = null;
	});

	it("BLOCKS projection into the de-id layer when consent is insufficient", async () => {
		setConsent("NONE");
		await expect(projectSubject(RECORD)).rejects.toBeInstanceOf(
			ConsentNotPermittedError,
		);
		// Data never crossed: no subject row, no provenance entry written.
		expect(prismaMock.deidentifiedSubject.upsert).not.toHaveBeenCalled();
		expect(prismaMock.provenanceLedgerEntry.create).not.toHaveBeenCalled();
	});

	it("BLOCKS when the user has no consent at all (null)", async () => {
		setConsent(null);
		await expect(projectSubject(RECORD)).rejects.toBeInstanceOf(
			ConsentNotPermittedError,
		);
	});

	it("ALLOWS projection when consent (CARE_TEAM) is sufficient", async () => {
		setConsent("CARE_TEAM", "v2");
		await expect(projectSubject(RECORD)).resolves.toBeTruthy();
		expect(prismaMock.deidentifiedSubject.upsert).toHaveBeenCalledTimes(1);
	});

	it("stamps the consent tier+version onto the provenance entry", async () => {
		setConsent("RESEARCH", "v9");
		await projectSubject(RECORD);
		const prov = (
			prismaMock.provenanceLedgerEntry.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		const meta = prov.metadata as Record<string, unknown>;
		expect(meta.consentTier).toBe("RESEARCH");
		expect(meta.consentVersion).toBe("v9");
		expect(meta.consentResolvedAt).toBeTypeOf("string");
	});
});

describe("DataPipeline consent gate — analytic / sale layer", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		state.current = null;
	});

	it("BLOCKS the analytic upsert when consent < RESEARCH", async () => {
		setConsent("CARE_TEAM");
		await expect(
			upsertAnalyticMetric({
				metric: "adherence",
				period: "2026-06",
				value: 0.9,
				consentUserId: "user-1",
			}),
		).rejects.toBeInstanceOf(ConsentNotPermittedError);
		expect(prismaMock.analyticMetric.upsert).not.toHaveBeenCalled();
	});

	it("ALLOWS the analytic upsert when consent >= RESEARCH and stamps it", async () => {
		setConsent("RESEARCH", "v4");
		await upsertAnalyticMetric({
			metric: "adherence",
			period: "2026-06",
			value: 0.9,
			consentUserId: "user-1",
		});
		expect(prismaMock.analyticMetric.upsert).toHaveBeenCalledTimes(1);
		const prov = (
			prismaMock.provenanceLedgerEntry.create.mock.calls[0][0] as {
				data: Record<string, unknown>;
			}
		).data;
		expect((prov.metadata as Record<string, unknown>).consentTier).toBe(
			"RESEARCH",
		);
	});

	it("requires COMMERCIAL_AI_TRAINING for a commercial/sale use", async () => {
		setConsent("RESEARCH");
		await expect(
			upsertAnalyticMetric({
				metric: "ai_training_set",
				period: "2026-06",
				value: 1,
				consentUserId: "user-1",
				requiredTier: "COMMERCIAL_AI_TRAINING",
			}),
		).rejects.toBeInstanceOf(ConsentNotPermittedError);
	});

	it("skips the consent gate entirely for system aggregates (no consentUserId)", async () => {
		await upsertAnalyticMetric({
			metric: "cohort_total",
			period: "2026-06",
			value: 5,
		});
		expect(prismaMock.analyticMetric.upsert).toHaveBeenCalledTimes(1);
	});
});
