import { logErr } from "@src/common/utils/safeLogger";
import { prisma } from "@src/lib/prisma";
import { recordAccess } from "@src/services/AuditService";
import { recordProvenance } from "@src/services/ProvenanceService";

/******************************************************************************
        In-product tiered consent capture (GTM-523)
******************************************************************************/

/**
 * Source-of-truth for a user's CONSENT state: an ordered, append-only history of
 * tiered consent decisions. The provenance ledger (ProvenanceService) and the
 * data pipeline (DataPipelineService) read the *current* consent from here and
 * stamp its tier + version onto every de-identified / analytic row, and only let
 * data cross into the analytic / sale layer when the user's current consent
 * permits that use (`isPermitted`).
 *
 * Tier model: tiers are ORDERED and each is a SUPERSET of the permissions of
 * every tier below it —
 *   NONE < CARE_TEAM < RESEARCH < COMMERCIAL_AI_TRAINING
 * so a user at tier T permits any use requiring tier <= T.
 *
 * Append-only: `recordConsent` / `revokeConsent` only ever INSERT rows; existing
 * rows are never mutated. The "current" consent is the latest non-revoked row
 * (by grantedAt, then id) for the user. Every change writes BOTH an AuditLog
 * entry and a ProvenanceLedgerEntry (reusing the existing services).
 */

/** The ordered consent tiers (mirrors the Prisma `ConsentTier` enum). */
export const CONSENT_TIERS = [
	"NONE",
	"CARE_TEAM",
	"RESEARCH",
	"COMMERCIAL_AI_TRAINING",
] as const;

export type ConsentTier = (typeof CONSENT_TIERS)[number];

/**
 * Numeric rank for each tier. Higher rank = broader (superset) permissions. The
 * ordering is the whole point of the model, so it is defined ONCE here and used
 * by `isPermitted` and by every downstream gate.
 */
export const CONSENT_TIER_RANK: Record<ConsentTier, number> = {
	NONE: 0,
	CARE_TEAM: 1,
	RESEARCH: 2,
	COMMERCIAL_AI_TRAINING: 3,
};

/** Type guard for an untrusted (client-supplied) tier string. */
export function isConsentTier(value: unknown): value is ConsentTier {
	return (
		typeof value === "string" &&
		(CONSENT_TIERS as readonly string[]).includes(value)
	);
}

/** A persisted consent row (the subset callers need). */
export interface ConsentRecord {
	id: string;
	userId: string;
	tier: ConsentTier;
	version: string;
	scopes: unknown;
	purpose: string | null;
	grantedAt: Date;
	revokedAt: Date | null;
}

/**
 * Pure tier check: does `consent` permit a use that REQUIRES `requiredTier`?
 *
 * A consent at tier T permits any required tier <= T (each tier is a superset of
 * the ones below it). A null/revoked consent permits only `NONE`. This is the
 * single gate every downstream layer calls — kept pure (no DB) so it is trivially
 * unit-testable.
 */
export function isPermitted(
	consent: Pick<ConsentRecord, "tier" | "revokedAt"> | null | undefined,
	requiredTier: ConsentTier,
): boolean {
	const requiredRank = CONSENT_TIER_RANK[requiredTier];
	// No consent, or a revoked one, only ever permits the NONE (rank 0) use.
	if (!consent || consent.revokedAt != null) {
		return requiredRank <= CONSENT_TIER_RANK.NONE;
	}
	return CONSENT_TIER_RANK[consent.tier] >= requiredRank;
}

/** Shape of a consent change for the audit/provenance side-effects. */
interface ConsentChangeContext {
	ip?: string | null;
	userAgent?: string | null;
}

/**
 * Fan out the mandatory side-effects of a consent change: an AuditLog entry AND
 * a ProvenanceLedgerEntry. Both reuse the existing, fail-open services so a
 * logging hiccup never blocks the consent write. NEVER passes PHI — only the
 * tier/version/action + opaque ids.
 */
function recordConsentSideEffects(
	action: "CREATE" | "UPDATE" | "DELETE",
	consent: ConsentRecord,
	ctx: ConsentChangeContext = {},
): void {
	void recordAccess({
		actorUserId: consent.userId,
		action,
		resourceType: "Consent",
		resourceId: consent.id,
		ip: ctx.ip ?? null,
		userAgent: ctx.userAgent ?? null,
		metadata: { tier: consent.tier, version: consent.version },
	});
	void recordProvenance({
		actorUserId: consent.userId,
		operation: action === "DELETE" ? "TRANSFORM" : "CREATE",
		layer: "IDENTIFIED",
		resourceType: "Consent",
		resourceId: consent.id,
		ip: ctx.ip ?? null,
		userAgent: ctx.userAgent ?? null,
		metadata: {
			tier: consent.tier,
			version: consent.version,
			revoked: consent.revokedAt != null,
		},
	});
}

export interface RecordConsentInput {
	userId: string;
	tier: ConsentTier;
	version: string;
	scopes?: unknown;
	purpose?: string | null;
	ip?: string | null;
	userAgent?: string | null;
}

/**
 * Append a new consent row for the user (record / update). Never mutates an
 * existing row — the new row becomes the user's current consent. Writes an
 * AuditLog + ProvenanceLedgerEntry for the change.
 */
export async function recordConsent(
	input: RecordConsentInput,
): Promise<ConsentRecord> {
	const row = (await prisma.consent.create({
		data: {
			userId: input.userId,
			tier: input.tier,
			version: input.version,
			scopes: (input.scopes as object | undefined) ?? undefined,
			purpose: input.purpose ?? undefined,
		},
	})) as ConsentRecord;

	recordConsentSideEffects("CREATE", row, {
		ip: input.ip,
		userAgent: input.userAgent,
	});
	return row;
}

/**
 * Revoke the user's CURRENT consent by appending a revoked row carrying the same
 * tier/version (append-only — the prior row is untouched). After this the user's
 * current consent resolves to null and only `NONE` uses are permitted. Returns
 * null when the user had no active consent to revoke.
 */
export async function revokeConsent(
	userId: string,
	ctx: ConsentChangeContext = {},
): Promise<ConsentRecord | null> {
	const current = await getCurrentConsent(userId);
	if (!current) return null;

	const row = (await prisma.consent.create({
		data: {
			userId,
			tier: current.tier,
			version: current.version,
			scopes: (current.scopes as object | null) ?? undefined,
			purpose: current.purpose ?? undefined,
			revokedAt: new Date(),
		},
	})) as ConsentRecord;

	recordConsentSideEffects("DELETE", row, ctx);
	return row;
}

/**
 * The user's CURRENT consent. Append-only resolution: take the user's LATEST row
 * (by grantedAt, then id) — the most recent consent decision wins. If that latest
 * decision is a revocation (`revokedAt` set), the user currently has no active
 * consent and null is returned. Returns null when the user has never consented.
 *
 * Resolving off the single latest row (rather than the latest row WHERE
 * revokedAt IS NULL) is what makes a revocation actually supersede an earlier
 * grant in an append-only table.
 */
export async function getCurrentConsent(
	userId: string,
): Promise<ConsentRecord | null> {
	const latest = (await prisma.consent.findFirst({
		where: { userId },
		orderBy: [{ grantedAt: "desc" }, { id: "desc" }],
	})) as ConsentRecord | null;
	if (!latest || latest.revokedAt != null) return null;
	return latest;
}

/**
 * The user's full consent history (newest first), including revoked rows. The
 * table is append-only so this is the complete, auditable record of every
 * consent decision.
 */
export async function getConsentHistory(
	userId: string,
): Promise<ConsentRecord[]> {
	return (await prisma.consent.findMany({
		where: { userId },
		orderBy: [{ grantedAt: "desc" }, { id: "desc" }],
	})) as ConsentRecord[];
}

/******************************************************************************
        IRB-integration stub (GTM-523 SEAM)
******************************************************************************/

/**
 * SEAM / NO-OP: future IRB study linkage. When the IRB integration lands, this
 * is where a RESEARCH-tier consent gets associated with a specific approved IRB
 * study (protocol id, approval window, PI). For now it only records the intent
 * to the provenance ledger and returns the (unlinked) consent unchanged — it
 * MUST stay a no-op so nothing downstream assumes a live IRB linkage exists.
 */
export async function linkIrbStudy(
	consentId: string,
	_irbStudyId: string,
): Promise<{ linked: false; consentId: string }> {
	try {
		void recordProvenance({
			operation: "ACCESS",
			layer: "IDENTIFIED",
			resourceType: "Consent",
			resourceId: consentId,
			// NON-PHI: only that an IRB-link was attempted; no study/patient detail.
			metadata: { irbLink: "stub" },
		});
	} catch (error) {
		logErr("ConsentService.linkIrbStudy stub failed", { error });
	}
	// Deliberately a no-op: no DB write, no real IRB call. Future work wires this.
	return { linked: false, consentId };
}

export const ConsentService = {
	CONSENT_TIERS,
	CONSENT_TIER_RANK,
	isConsentTier,
	isPermitted,
	recordConsent,
	revokeConsent,
	getCurrentConsent,
	getConsentHistory,
	linkIrbStudy,
};

export default ConsentService;
