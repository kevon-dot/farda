import { createHash } from "node:crypto";
import { prisma } from "@src/lib/prisma";

/******************************************************************************
        Provenance ledger — 3-layer data lineage (GTM-522)
******************************************************************************/

/**
 * Append-only, tamper-evident provenance ledger recording who/what/when for
 * every record creation / transform / access / export across the three data
 * layers (identified -> de-identified -> analytic).
 *
 * Tamper-evidence mirrors the AuditService hash chain EXACTLY: each row stores
 * `hash = sha256(prevHash + canonical(entry))` where `prevHash` is the `hash`
 * of the immediately-preceding row. Editing or deleting any historical row
 * breaks every subsequent hash and is therefore detectable. The table is
 * append-only (no updates/deletes).
 *
 * PHI safety: only layer names, operation types, opaque record ids / pseudonyms
 * and non-PHI metadata are recorded. PHI *values* (medication names, notes,
 * exact dates, real user ids surfaced as data, etc.) must NEVER be passed in —
 * the ledger must not itself become a PHI leak.
 */

export type ProvenanceOperation = "CREATE" | "TRANSFORM" | "ACCESS" | "EXPORT";
export type DataLayer = "IDENTIFIED" | "DEIDENTIFIED" | "ANALYTIC";

export interface RecordProvenanceInput {
	/** The acting session user, or null/undefined for system/background work. */
	actorUserId?: string | null;
	operation: ProvenanceOperation;
	/** The data layer this entry concerns. */
	layer: DataLayer;
	/** For TRANSFORM rows: the layer the data was projected FROM. */
	sourceLayer?: DataLayer | null;
	/** e.g. "Dose" | "DeidentifiedEvent" | "AnalyticMetric". */
	resourceType: string;
	/** Opaque cuid or PSEUDONYM. NEVER a raw identifier value. */
	resourceId?: string | null;
	ip?: string | null;
	userAgent?: string | null;
	/** Non-PHI structured context only (counts, period, route). NEVER PHI. */
	metadata?: Record<string, unknown> | null;
}

/**
 * Deterministically serialise the entry so the same logical entry always hashes
 * to the same value (stable key ordering). Used as the chained content.
 * Identical to AuditService.canonicalize so both ledgers behave the same way.
 */
function canonicalize(entry: Record<string, unknown>): string {
	const sortValue = (value: unknown): unknown => {
		if (value === null || typeof value !== "object") {
			return value;
		}
		if (Array.isArray(value)) {
			return value.map(sortValue);
		}
		const sorted: Record<string, unknown> = {};
		for (const key of Object.keys(value as Record<string, unknown>).sort()) {
			sorted[key] = sortValue((value as Record<string, unknown>)[key]);
		}
		return sorted;
	};
	return JSON.stringify(sortValue(entry));
}

/**
 * Compute the chained content hash for a new ledger row.
 * `hash = sha256(prevHash + canonical(entry))`.
 */
export function computeHash(
	prevHash: string | null,
	entry: Record<string, unknown>,
): string {
	return createHash("sha256")
		.update(`${prevHash ?? ""}${canonicalize(entry)}`)
		.digest("hex");
}

/**
 * Build the strictly non-PHI hashed content for an entry. Excludes volatile
 * fields (id/createdAt) so the hash depends only on the logged facts + the
 * previous hash. Exported so the verifier recomputes the SAME content.
 */
export function contentFor(
	input: RecordProvenanceInput,
): Record<string, unknown> {
	return {
		actorUserId: input.actorUserId ?? null,
		operation: input.operation,
		layer: input.layer,
		sourceLayer: input.sourceLayer ?? null,
		resourceType: input.resourceType,
		resourceId: input.resourceId ?? null,
		ip: input.ip ?? null,
		userAgent: input.userAgent ?? null,
		metadata: input.metadata ?? null,
	};
}

/**
 * Append a single provenance entry, chaining off the latest row.
 *
 * FAIL-SAFE (fail-open): if writing the row throws, the error is logged
 * server-side but is NOT re-thrown, so a ledger hiccup never breaks the data
 * pipeline. (Mirrors AuditService.recordAccess; flip the catch to re-throw for
 * a fail-closed posture.)
 */
export async function recordProvenance(
	input: RecordProvenanceInput,
): Promise<void> {
	try {
		const previous = await prisma.provenanceLedgerEntry.findFirst({
			orderBy: [{ createdAt: "desc" }, { id: "desc" }],
			select: { hash: true },
		});
		const prevHash = previous?.hash ?? null;

		const content = contentFor(input);
		const hash = computeHash(prevHash, content);

		await prisma.provenanceLedgerEntry.create({
			data: {
				actorUserId: content.actorUserId as string | null,
				operation: content.operation as string,
				layer: content.layer as string,
				sourceLayer: content.sourceLayer as string | null,
				resourceType: content.resourceType as string,
				resourceId: content.resourceId as string | null,
				ip: content.ip as string | null,
				userAgent: content.userAgent as string | null,
				metadata: (content.metadata as Record<string, unknown>) ?? undefined,
				prevHash,
				hash,
			},
		});
	} catch (error) {
		console.error("ProvenanceService.recordProvenance failed", {
			operation: input.operation,
			layer: input.layer,
			resourceType: input.resourceType,
			error,
		});
	}
}

/** A persisted ledger row, as needed to verify the chain. */
export interface LedgerRow {
	actorUserId: string | null;
	operation: string;
	layer: string;
	sourceLayer: string | null;
	resourceType: string;
	resourceId: string | null;
	ip: string | null;
	userAgent: string | null;
	metadata: Record<string, unknown> | null;
	prevHash: string | null;
	hash: string;
}

export interface VerifyResult {
	valid: boolean;
	/** Index of the first row that fails verification, or null when all valid. */
	brokenAtIndex: number | null;
	checked: number;
}

/**
 * Verify a chronologically-ordered slice of the ledger. A row is valid when:
 *   - its `prevHash` equals the previous row's `hash` (chain linkage), and
 *   - its `hash` equals sha256(prevHash + canonical(content)) (content match).
 *
 * Pure function over the supplied rows (no DB) so it is unit-testable. Any
 * tamper — mutating a field, reordering, or removing a row — breaks one of the
 * two checks and is reported.
 */
export function verifyChain(rows: LedgerRow[]): VerifyResult {
	let prevHash: string | null = null;
	for (let i = 0; i < rows.length; i++) {
		const row = rows[i];
		// Chain linkage: this row must point at the previous row's hash.
		if ((row.prevHash ?? null) !== prevHash) {
			return { valid: false, brokenAtIndex: i, checked: rows.length };
		}
		// Content integrity: recompute the hash from the row's own content.
		const expected = computeHash(prevHash, contentFor(row));
		if (expected !== row.hash) {
			return { valid: false, brokenAtIndex: i, checked: rows.length };
		}
		prevHash = row.hash;
	}
	return { valid: true, brokenAtIndex: null, checked: rows.length };
}

/**
 * Load the full ledger in chain order and verify it against the live DB.
 * Convenience wrapper around `verifyChain` for an admin integrity check.
 */
export async function verifyLedger(): Promise<VerifyResult> {
	const rows = (await prisma.provenanceLedgerEntry.findMany({
		orderBy: [{ createdAt: "asc" }, { id: "asc" }],
		select: {
			actorUserId: true,
			operation: true,
			layer: true,
			sourceLayer: true,
			resourceType: true,
			resourceId: true,
			ip: true,
			userAgent: true,
			metadata: true,
			prevHash: true,
			hash: true,
		},
	})) as LedgerRow[];
	return verifyChain(rows);
}

export const ProvenanceService = {
	recordProvenance,
	verifyChain,
	verifyLedger,
	computeHash,
	contentFor,
};

export default ProvenanceService;
