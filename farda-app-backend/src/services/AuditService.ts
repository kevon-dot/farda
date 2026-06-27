import { createHash } from "node:crypto";
import { prisma } from "@src/lib/prisma";

/******************************************************************************
                        HIPAA PHI audit trail (GTM-512, #6)
******************************************************************************/

/**
 * Tamper-evident, append-only audit logging of PHI access (HIPAA §164.312(b)).
 *
 * Tamper-evidence: each row stores `hash = sha256(prevHash + canonical(entry))`
 * where `prevHash` is the `hash` of the immediately-preceding row. This forms a
 * hash chain -- editing or deleting any historical row breaks every subsequent
 * hash and is therefore detectable. The table is append-only (no updates/deletes).
 *
 * PHI safety: only resource ids/types/actions and request metadata are recorded.
 * PHI *values* (medication names, notes, etc.) must NEVER be passed in -- the
 * audit trail must not itself become a PHI leak.
 */

export type AuditAction = "READ" | "CREATE" | "UPDATE" | "DELETE";

export interface RecordAccessInput {
	/** The acting session user, or null/undefined for system/background actions. */
	actorUserId?: string | null;
	action: AuditAction;
	/** e.g. "Prescription" | "Dose" | "Medicine" | "User". */
	resourceType: string;
	resourceId?: string | null;
	ip?: string | null;
	userAgent?: string | null;
	/** Non-PHI structured context only (counts, route, etc.). NEVER PHI values. */
	metadata?: Record<string, unknown> | null;
}

/**
 * Deterministically serialise the audit entry so the same logical entry always
 * hashes to the same value (stable key ordering). Used as the chained content.
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
 * Compute the chained content hash for a new audit row.
 * `hash = sha256(prevHash + canonical(entry))`.
 */
function computeHash(
	prevHash: string | null,
	entry: Record<string, unknown>,
): string {
	return createHash("sha256")
		.update(`${prevHash ?? ""}${canonicalize(entry)}`)
		.digest("hex");
}

/**
 * Record a single PHI-access audit entry.
 *
 * FAIL-SAFE (fail-open): if writing the audit row throws, the error is logged
 * server-side but is NOT re-thrown, so an audit-store hiccup never denies care
 * by breaking the main request.
 *
 * NOTE: a stricter HIPAA posture may require fail-CLOSED (reject the request
 * when the access cannot be audited). That trade-off is deliberately left to
 * the caller / a follow-up; flip the catch below to re-throw to enforce it.
 */
export async function recordAccess(input: RecordAccessInput): Promise<void> {
	try {
		// Read the latest row's hash to chain off it. Ordering by createdAt then
		// id keeps this deterministic even within the same millisecond.
		const previous = await prisma.auditLog.findFirst({
			orderBy: [{ createdAt: "desc" }, { id: "desc" }],
			select: { hash: true },
		});
		const prevHash = previous?.hash ?? null;

		// The hashed content excludes volatile fields (id/createdAt) so it depends
		// only on the logged facts + the previous hash. Strictly non-PHI fields.
		const content = {
			actorUserId: input.actorUserId ?? null,
			action: input.action,
			resourceType: input.resourceType,
			resourceId: input.resourceId ?? null,
			ip: input.ip ?? null,
			userAgent: input.userAgent ?? null,
			metadata: input.metadata ?? null,
		};

		const hash = computeHash(prevHash, content);

		await prisma.auditLog.create({
			data: {
				actorUserId: content.actorUserId,
				action: content.action,
				resourceType: content.resourceType,
				resourceId: content.resourceId,
				ip: content.ip,
				userAgent: content.userAgent,
				metadata: content.metadata ?? undefined,
				prevHash,
				hash,
			},
		});
	} catch (error) {
		// Fail-open: never break the main request because auditing failed.
		console.error("AuditService.recordAccess failed", {
			action: input.action,
			resourceType: input.resourceType,
			resourceId: input.resourceId ?? null,
			error,
		});
	}
}

export const AuditService = { recordAccess };

export default AuditService;
