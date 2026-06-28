import { prisma } from "@src/lib/prisma";
import { type AuditAction, recordAccess } from "@src/services/AuditService";
import { revokeConsent } from "@src/services/ConsentService";
import {
	type ProvenanceOperation,
	recordProvenance,
} from "@src/services/ProvenanceService";

/******************************************************************************
        Data retention, deletion/export & consent-revocation (GTM-542)
*******************************************************************************

  Builds ON the GTM-522 3-layer store + GTM-523 consent model. This service is
  the data-subject-rights engine:

    * applyRetention  — select (and act on) IDENTIFIED-layer records past their
                        per-class retention window, EXEMPTING legal-hold classes.
                        The selection math is a PURE function (selectExpired) so
                        it is unit-testable; the scheduled sweep is infra.
    * requestExport / buildExport     — assemble the user's identified-layer data
                        into a portable structure (data-subject access /
                        portability). IDOR-scoped: only the requesting user's data.
    * requestDeletion / processDeletion — erase the user's IDENTIFIED (service)
                        layer data (right to erasure). Also revokes consent so no
                        FUTURE projection occurs.

  --------------------------------------------------------------------------
  CRITICAL CORRECTNESS BOUNDARY — "can't recall de-identified":
  --------------------------------------------------------------------------
  Deletion / retention erase the IDENTIFIED (service) layer ONLY. Already-
  projected DE-IDENTIFIED (DeidentifiedSubject/Event) and ANALYTIC
  (AnalyticMetric) rows are NOT recalled or deleted: by construction they carry
  NO re-identifying link back to the user (one-way salted pseudonym; no user FK;
  HIPAA Safe-Harbor). This mirrors the "can't untrain / can't recall
  de-identified" disclosure — once data has been de-identified and projected, it
  cannot be pulled back.

  What revocation DOES do is STOP FUTURE projection: the GTM-523 consent gate
  (DataPipelineService.assertConsentForLayer -> ConsentService.isPermitted)
  already fail-closes once the user's current consent resolves to NONE (which a
  revocation produces). We RELY on that existing gate; deletion additionally
  revokes consent to guarantee it.

  Every action writes an AuditLog AND a ProvenanceLedgerEntry (reusing the
  existing services). Both are PHI-free: only counts / ids / classes.
******************************************************************************/

/** The IDENTIFIED (service) layer tables a user owns, erased on deletion. */
export const IDENTIFIED_DATA_CLASSES = [
	"Prescription",
	"Medicine",
	"Dose",
	"ReminderResponseEvent",
	"RefillEvent",
	"PushToken",
	"Consent",
] as const;

export type IdentifiedDataClass = (typeof IDENTIFIED_DATA_CLASSES)[number];

/* ===========================================================================
   RETENTION — pure selection + acting sweep
   =========================================================================== */

/** A retention policy row (the subset the selection logic needs). */
export interface RetentionPolicyRecord {
	dataClass: string;
	retentionDays: number;
	legalHold: boolean;
}

/** A minimal record considered for retention (id + creation time + class). */
export interface RetainableRecord {
	id: string;
	dataClass: string;
	createdAt: Date;
}

/** The outcome of a retention selection: what to delete and what was exempt. */
export interface RetentionSelection {
	/** Records eligible for deletion (past window, class NOT under legal hold). */
	expired: RetainableRecord[];
	/** Records skipped because their class is under legal hold. */
	legalHoldExempt: RetainableRecord[];
	/** Records inside their retention window (kept). */
	withinWindow: RetainableRecord[];
}

/**
 * PURE retention selection. Given the policies (per data class) and a set of
 * candidate records, partition them into:
 *   - `expired`         — past their window AND not under legal hold (delete),
 *   - `legalHoldExempt` — class under legal hold (never deleted, any age),
 *   - `withinWindow`    — still inside the retention window (keep).
 *
 * A record is past its window when `now - createdAt > retentionDays`. Records
 * whose class has NO policy are treated as "keep" (withinWindow) — retention
 * deletion is opt-in per class, never a default. No DB access, so trivially
 * unit-testable.
 */
export function selectExpired(
	policies: RetentionPolicyRecord[],
	records: RetainableRecord[],
	now: Date,
): RetentionSelection {
	const byClass = new Map<string, RetentionPolicyRecord>();
	for (const p of policies) byClass.set(p.dataClass, p);

	const expired: RetainableRecord[] = [];
	const legalHoldExempt: RetainableRecord[] = [];
	const withinWindow: RetainableRecord[] = [];

	const MS_PER_DAY = 24 * 60 * 60 * 1000;

	for (const rec of records) {
		const policy = byClass.get(rec.dataClass);
		// No policy for this class => not subject to retention deletion. Keep it.
		if (!policy) {
			withinWindow.push(rec);
			continue;
		}
		// Legal hold exempts the entire class regardless of age.
		if (policy.legalHold) {
			legalHoldExempt.push(rec);
			continue;
		}
		const ageMs = now.getTime() - rec.createdAt.getTime();
		const windowMs = policy.retentionDays * MS_PER_DAY;
		if (ageMs > windowMs) {
			expired.push(rec);
		} else {
			withinWindow.push(rec);
		}
	}

	return { expired, legalHoldExempt, withinWindow };
}

/** A prisma delegate that can bulk-delete rows by a where filter. */
interface DeletableDelegate {
	deleteMany: (args: { where: unknown }) => Promise<{ count: number }>;
}

/** A prisma delegate that can list rows (id + createdAt) for a class. */
interface ListableDelegate {
	findMany: (args: {
		select: { id: true; createdAt: true };
	}) => Promise<Array<{ id: string; createdAt: Date }>>;
}

/** Map of a data class -> the prisma delegate that owns its rows. */
function delegateFor(dataClass: string): DeletableDelegate | null {
	const map: Record<string, DeletableDelegate | undefined> = {
		Prescription: prisma.prescription as unknown as DeletableDelegate,
		Medicine: prisma.medicine as unknown as DeletableDelegate,
		Dose: prisma.dose as unknown as DeletableDelegate,
		ReminderResponseEvent:
			prisma.reminderResponseEvent as unknown as DeletableDelegate,
		RefillEvent: prisma.refillEvent as unknown as DeletableDelegate,
		PushToken: prisma.pushToken as unknown as DeletableDelegate,
		Consent: prisma.consent as unknown as DeletableDelegate,
	};
	return map[dataClass] ?? null;
}

/** A read-only delegate that can list rows for a class (for retention scan). */
function readDelegateFor(dataClass: string): ListableDelegate | null {
	const map: Record<string, ListableDelegate | undefined> = {
		Prescription: prisma.prescription as unknown as ListableDelegate,
		Medicine: prisma.medicine as unknown as ListableDelegate,
		Dose: prisma.dose as unknown as ListableDelegate,
		ReminderResponseEvent:
			prisma.reminderResponseEvent as unknown as ListableDelegate,
		RefillEvent: prisma.refillEvent as unknown as ListableDelegate,
		PushToken: prisma.pushToken as unknown as ListableDelegate,
	};
	return map[dataClass] ?? null;
}

export interface ApplyRetentionResult {
	/** Per-class count of records deleted by this run. */
	deletedByClass: Record<string, number>;
	/** Per-class count of records exempted because of a legal hold. */
	legalHoldExemptByClass: Record<string, number>;
	/** Total records deleted across all classes. */
	totalDeleted: number;
}

/**
 * Apply retention as of `now`: load every active RetentionPolicy, scan the
 * candidate records for each governed class, select the expired (non-legal-hold)
 * ones via the PURE `selectExpired`, and delete them from the IDENTIFIED layer.
 *
 * IMPORTANT: this only touches the IDENTIFIED (service) layer. De-identified /
 * analytic rows are NEVER swept here — they carry no user link and are not
 * recalled (see the file header). Writes an AuditLog + ProvenanceLedgerEntry
 * with PHI-free counts.
 */
export async function applyRetention(
	now: Date = new Date(),
): Promise<ApplyRetentionResult> {
	const policies =
		(await prisma.retentionPolicy.findMany()) as RetentionPolicyRecord[];

	const deletedByClass: Record<string, number> = {};
	const legalHoldExemptByClass: Record<string, number> = {};
	let totalDeleted = 0;

	for (const policy of policies) {
		const reader = readDelegateFor(policy.dataClass);
		if (!reader) continue;

		const rows = await reader.findMany({
			select: { id: true, createdAt: true },
		});

		const candidates: RetainableRecord[] = rows.map((r) => ({
			id: r.id,
			dataClass: policy.dataClass,
			createdAt: r.createdAt,
		}));

		const selection = selectExpired([policy], candidates, now);

		if (selection.legalHoldExempt.length > 0) {
			legalHoldExemptByClass[policy.dataClass] =
				selection.legalHoldExempt.length;
		}

		if (selection.expired.length > 0) {
			const writer = delegateFor(policy.dataClass);
			if (writer) {
				await writer.deleteMany({
					where: { id: { in: selection.expired.map((r) => r.id) } },
				});
			}
			deletedByClass[policy.dataClass] = selection.expired.length;
			totalDeleted += selection.expired.length;
		}
	}

	await recordRights("RetentionPolicy", null, "DELETE", "TRANSFORM", {
		action: "applyRetention",
		deletedByClass,
		legalHoldExemptByClass,
		totalDeleted,
	});

	return { deletedByClass, legalHoldExemptByClass, totalDeleted };
}

/* ===========================================================================
   EXPORT — data-subject access / portability
   =========================================================================== */

/** The portable, identified-layer export payload for one user. */
export interface UserExport {
	userId: string;
	exportedAt: string;
	/** Identity profile (the user's own PHI; this is a data-subject access). */
	user: Record<string, unknown> | null;
	prescriptions: Array<Record<string, unknown>>;
	medicines: Array<Record<string, unknown>>;
	doses: Array<Record<string, unknown>>;
	reminderResponseEvents: Array<Record<string, unknown>>;
	refillEvents: Array<Record<string, unknown>>;
	consents: Array<Record<string, unknown>>;
}

/**
 * Assemble the user's IDENTIFIED-layer data into a portable structure. Every
 * query is scoped to `userId` (IDOR: NEVER returns another user's data). This is
 * a data-subject ACCESS, so it intentionally includes the user's own PHI.
 *
 * De-identified / analytic rows are NOT included — they are pseudonymous and
 * cannot be tied back to the user, so they are out of scope for a per-user
 * access/portability export.
 */
export async function buildExport(userId: string): Promise<UserExport> {
	const [
		user,
		prescriptions,
		doses,
		reminderResponseEvents,
		refillEvents,
		consents,
	] = await Promise.all([
		prisma.user.findUnique({ where: { id: userId } }),
		prisma.prescription.findMany({ where: { userId } }),
		prisma.dose.findMany({ where: { userId } }),
		prisma.reminderResponseEvent.findMany({ where: { userId } }),
		prisma.refillEvent.findMany({ where: { userId } }),
		prisma.consent.findMany({ where: { userId } }),
	]);

	// Medicines hang off the user's prescriptions (no direct userId column), so
	// scope them through the already-IDOR-scoped prescription ids.
	const prescriptionIds = (prescriptions as Array<{ id: string }>).map(
		(p) => p.id,
	);
	const medicines =
		prescriptionIds.length > 0
			? await prisma.medicine.findMany({
					where: { prescriptionId: { in: prescriptionIds } },
				})
			: [];

	const payload: UserExport = {
		userId,
		exportedAt: new Date().toISOString(),
		user: (user as Record<string, unknown> | null) ?? null,
		prescriptions: prescriptions as Array<Record<string, unknown>>,
		medicines: medicines as Array<Record<string, unknown>>,
		doses: doses as Array<Record<string, unknown>>,
		reminderResponseEvents: reminderResponseEvents as Array<
			Record<string, unknown>
		>,
		refillEvents: refillEvents as Array<Record<string, unknown>>,
		consents: consents as Array<Record<string, unknown>>,
	};

	// Audit + provenance: an EXPORT of the identified layer (PHI-free counts only).
	await recordRights("User", userId, "READ", "EXPORT", {
		action: "buildExport",
		counts: {
			prescriptions: payload.prescriptions.length,
			medicines: payload.medicines.length,
			doses: payload.doses.length,
			reminderResponseEvents: payload.reminderResponseEvents.length,
			refillEvents: payload.refillEvents.length,
			consents: payload.consents.length,
		},
	});

	return payload;
}

export interface ExportRequestRecord {
	id: string;
	userId: string;
	status: string;
	format: string;
	requestedAt: Date;
	completedAt: Date | null;
}

/**
 * Create an export request row (PENDING) for the user. The portable payload is
 * built on demand by `buildExport` (the row tracks the lifecycle only; no PHI is
 * stored on it). Writes an AuditLog + ProvenanceLedgerEntry.
 */
export async function requestExport(
	userId: string,
	format = "json",
): Promise<ExportRequestRecord> {
	const row = (await prisma.exportRequest.create({
		data: { userId, status: "PENDING", format },
	})) as ExportRequestRecord;

	await recordRights("ExportRequest", row.id, "CREATE", "ACCESS", {
		action: "requestExport",
		format,
	});
	return row;
}

/** The user's latest export request (newest first), or null. */
export async function getExportStatus(
	userId: string,
): Promise<ExportRequestRecord | null> {
	return (await prisma.exportRequest.findFirst({
		where: { userId },
		orderBy: [{ requestedAt: "desc" }, { id: "desc" }],
	})) as ExportRequestRecord | null;
}

/* ===========================================================================
   DELETION — right to erasure (identified layer ONLY)
   =========================================================================== */

export interface DeletionRequestRecord {
	id: string;
	userId: string;
	status: string;
	scope: string;
	triggeredByRevocation: boolean;
	requestedAt: Date;
	completedAt: Date | null;
}

export interface RequestDeletionOptions {
	triggeredByRevocation?: boolean;
	/**
	 * When true (the default), creating the deletion request also REVOKES the
	 * user's current consent so no FUTURE projection occurs (we rely on the
	 * GTM-523 consent gate to fail-close once consent is NONE). Set false when the
	 * caller has already revoked (e.g. the revocation->deletion path) to avoid a
	 * double revoke.
	 */
	revokeConsentToo?: boolean;
	ip?: string | null;
	userAgent?: string | null;
}

/**
 * Create a deletion request (PENDING) for the user and, by default, revoke their
 * current consent so future projection stops (GTM-523 gate). The actual erasure
 * runs in `processDeletion`. Writes an AuditLog + ProvenanceLedgerEntry.
 *
 * The "can't recall de-identified" boundary applies: this request erases the
 * IDENTIFIED layer only; de-identified / analytic rows are not recalled.
 */
export async function requestDeletion(
	userId: string,
	opts: RequestDeletionOptions = {},
): Promise<DeletionRequestRecord> {
	const triggeredByRevocation = opts.triggeredByRevocation ?? false;
	const revokeConsentToo = opts.revokeConsentToo ?? true;

	const row = (await prisma.deletionRequest.create({
		data: {
			userId,
			status: "PENDING",
			scope: "FULL",
			triggeredByRevocation,
		},
	})) as DeletionRequestRecord;

	// Stop FUTURE projection: revoking consent makes the GTM-523 gate fail-closed
	// (current consent resolves to NONE). Already-projected de-id/analytic rows
	// are NOT recalled — see the file header boundary.
	if (revokeConsentToo) {
		await revokeConsent(userId, { ip: opts.ip, userAgent: opts.userAgent });
	}

	await recordRights("DeletionRequest", row.id, "CREATE", "ACCESS", {
		action: "requestDeletion",
		triggeredByRevocation,
		scope: "FULL",
	});
	return row;
}

export interface ProcessDeletionResult {
	request: DeletionRequestRecord | null;
	/** Per-class count of identified-layer rows erased. */
	deletedByClass: Record<string, number>;
	/**
	 * Always false: de-identified / analytic rows are NOT recalled by deletion.
	 * Exposed explicitly so callers/tests can assert the boundary.
	 */
	deidentifiedRecalled: false;
}

/**
 * Process the user's pending deletion: erase the IDENTIFIED (service) layer in
 * FK-safe order (children before parents) and mark the latest request COMPLETED.
 *
 * BOUNDARY (mirrors the file header): this erases ONLY the identified layer.
 * De-identified (DeidentifiedSubject/Event) and analytic (AnalyticMetric) rows
 * are deliberately left intact — they are pseudonymous, carry no user FK, and
 * cannot be recalled ("can't recall de-identified"). `deidentifiedRecalled` is
 * hard-coded false to make that contract explicit.
 *
 * Writes an AuditLog + ProvenanceLedgerEntry (PHI-free counts).
 */
export async function processDeletion(
	userId: string,
): Promise<ProcessDeletionResult> {
	const pending = (await prisma.deletionRequest.findFirst({
		where: { userId, status: { in: ["PENDING", "PROCESSING"] } },
		orderBy: [{ requestedAt: "asc" }, { id: "asc" }],
	})) as DeletionRequestRecord | null;

	if (pending) {
		await prisma.deletionRequest.update({
			where: { id: pending.id },
			data: { status: "PROCESSING" },
		});
	}

	const deletedByClass: Record<string, number> = {};

	// Erase the identified layer. Order matters for FK integrity: delete child
	// rows (and rows referencing Dose/Prescription) before the parents. Several
	// tables ON DELETE SET NULL / CASCADE from User, but we erase explicitly so
	// the contract does not depend on cascade configuration.
	const erasureOrder: Array<{ dataClass: string; where: object }> = [
		{ dataClass: "ReminderResponseEvent", where: { userId } },
		{ dataClass: "RefillEvent", where: { userId } },
		{ dataClass: "Dose", where: { userId } },
		{ dataClass: "Medicine", where: { prescription: { userId } } },
		{ dataClass: "Prescription", where: { userId } },
		{ dataClass: "PushToken", where: { userId } },
		{ dataClass: "Consent", where: { userId } },
	];

	for (const step of erasureOrder) {
		const writer = delegateFor(step.dataClass);
		if (!writer) continue;
		const res = await writer.deleteMany({ where: step.where });
		if (res?.count) deletedByClass[step.dataClass] = res.count;
	}

	let completed: DeletionRequestRecord | null = pending;
	if (pending) {
		completed = (await prisma.deletionRequest.update({
			where: { id: pending.id },
			data: { status: "COMPLETED", completedAt: new Date() },
		})) as DeletionRequestRecord;
	}

	await recordRights(
		"DeletionRequest",
		pending?.id ?? null,
		"DELETE",
		"TRANSFORM",
		{
			action: "processDeletion",
			deletedByClass,
			// Explicit non-recall of the de-identified / analytic layers.
			deidentifiedRecalled: false,
		},
	);

	return { request: completed, deletedByClass, deidentifiedRecalled: false };
}

/**
 * Consent-revocation -> deletion WORKFLOW (GTM-542).
 *
 * The single entry point that ties a consent revocation to the erasure workflow:
 *   1. Revoke the user's current consent (GTM-523). This alone STOPS FUTURE
 *      projection — the consent gate (DataPipelineService.assertConsentForLayer)
 *      fail-closes once current consent resolves to NONE.
 *   2. Create a deletion request for the IDENTIFIED layer, flagged
 *      `triggeredByRevocation`. We pass `revokeConsentToo: false` so we do not
 *      double-revoke (step 1 already did it).
 *
 * Returns both the revoked consent row (null if the user had no active consent)
 * and the deletion request. The de-identified / analytic layers are NOT recalled
 * — see the file-header boundary.
 */
export async function revokeConsentAndDelete(
	userId: string,
	ctx: { ip?: string | null; userAgent?: string | null } = {},
): Promise<{
	consent: Awaited<ReturnType<typeof revokeConsent>>;
	deletion: DeletionRequestRecord;
}> {
	// Step 1: revoke consent -> stops FUTURE projection via the existing gate.
	const consent = await revokeConsent(userId, ctx);

	// Step 2: queue erasure of the identified layer (consent already revoked).
	const deletion = await requestDeletion(userId, {
		triggeredByRevocation: true,
		revokeConsentToo: false,
		ip: ctx.ip,
		userAgent: ctx.userAgent,
	});

	return { consent, deletion };
}

/** The user's latest deletion request (newest first), or null. */
export async function getDeletionStatus(
	userId: string,
): Promise<DeletionRequestRecord | null> {
	return (await prisma.deletionRequest.findFirst({
		where: { userId },
		orderBy: [{ requestedAt: "desc" }, { id: "desc" }],
	})) as DeletionRequestRecord | null;
}

/* ===========================================================================
   Audit + provenance fan-out (PHI-free)
   =========================================================================== */

/**
 * Fan out the mandatory side-effects of a data-rights action: an AuditLog entry
 * AND a ProvenanceLedgerEntry on the IDENTIFIED layer. Both reuse the existing,
 * fail-open services. NEVER passes PHI — only counts / ids / classes.
 */
async function recordRights(
	resourceType: string,
	resourceId: string | null,
	auditAction: AuditAction,
	provenanceOp: ProvenanceOperation,
	metadata: Record<string, unknown>,
): Promise<void> {
	await recordAccess({
		action: auditAction,
		resourceType,
		resourceId,
		metadata,
	});
	await recordProvenance({
		operation: provenanceOp,
		layer: "IDENTIFIED",
		resourceType,
		resourceId,
		metadata,
	});
}

export const DataRetentionService = {
	IDENTIFIED_DATA_CLASSES,
	selectExpired,
	applyRetention,
	buildExport,
	requestExport,
	getExportStatus,
	requestDeletion,
	processDeletion,
	revokeConsentAndDelete,
	getDeletionStatus,
};

export default DataRetentionService;
