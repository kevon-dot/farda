import { prisma } from "@src/lib/prisma";
import {
	type ConsentRecord,
	type ConsentTier,
	getCurrentConsent,
	isPermitted,
} from "@src/services/ConsentService";
import {
	type DeidentifiedEventRecord,
	type DeidentifiedSubjectRecord,
	deidentifyEvent,
	deidentifySubject,
	type IdentifiedEvent,
	type IdentifiedRecord,
} from "@src/services/DeidentificationService";
import { recordProvenance } from "@src/services/ProvenanceService";

/******************************************************************************
        Data pipeline seam — identified -> de-identified -> analytic (GTM-522)
******************************************************************************/

/**
 * Thin projection seam that moves data between the three layers, writing a
 * provenance entry for every transform/access. The de-identification math lives
 * in the pure DeidentificationService; this module is the persistence + lineage
 * glue.
 *
 * IMPORTANT: only de-identified, PHI-free values are written to the de-id /
 * analytic tables and to the provenance ledger. The identified (PHI) layer is
 * never copied verbatim.
 */

/**
 * The required consent tier to project data INTO each layer. Crossing into the
 * de-identified layer requires (at least) CARE_TEAM consent; crossing into the
 * ANALYTIC / sale layer requires RESEARCH (commercial use additionally needs
 * COMMERCIAL_AI_TRAINING, enforced per metric where applicable). The data
 * pipeline calls `isPermitted(currentConsent, requiredTier)` before persisting.
 */
export const LAYER_REQUIRED_TIER: Record<
	"DEIDENTIFIED" | "ANALYTIC",
	ConsentTier
> = {
	DEIDENTIFIED: "CARE_TEAM",
	ANALYTIC: "RESEARCH",
};

/** Raised when a user's current consent does not permit the requested layer use. */
export class ConsentNotPermittedError extends Error {
	constructor(
		public readonly requiredTier: ConsentTier,
		public readonly currentTier: ConsentTier | "NONE",
	) {
		super(
			`Consent insufficient: requires ${requiredTier}, user is at ${currentTier}`,
		);
		this.name = "ConsentNotPermittedError";
	}
}

/**
 * Consent stamp recorded on every cross-layer provenance entry: the consent TIER
 * + document VERSION in effect for the user at projection time, and when it was
 * resolved. This is "consent state on every record" (GTM-523). A user with no
 * current consent is stamped as tier NONE / version null.
 */
export interface ConsentStamp {
	consentTier: ConsentTier | "NONE";
	consentVersion: string | null;
	consentResolvedAt: string;
}

/**
 * Resolve the user's CURRENT consent into a stamp. Wired to the
 * ConsentService source-of-truth (replacing any GTM-522 placeholder). A user
 * with no active consent resolves to tier NONE / null version.
 */
export async function resolveConsentStamp(
	userId: string,
): Promise<{ consent: ConsentRecord | null; stamp: ConsentStamp }> {
	const consent = await getCurrentConsent(userId);
	return {
		consent,
		stamp: {
			consentTier: consent?.tier ?? "NONE",
			consentVersion: consent?.version ?? null,
			consentResolvedAt: new Date().toISOString(),
		},
	};
}

/**
 * Enforce that the user's current consent permits projecting into `layer`,
 * returning the consent stamp to record on the resulting rows. Fail-closed:
 * throws ConsentNotPermittedError when consent is insufficient so data never
 * crosses into a layer the user has not consented to.
 */
export async function assertConsentForLayer(
	userId: string,
	layer: "DEIDENTIFIED" | "ANALYTIC",
): Promise<ConsentStamp> {
	const { consent, stamp } = await resolveConsentStamp(userId);
	const required = LAYER_REQUIRED_TIER[layer];
	if (!isPermitted(consent, required)) {
		throw new ConsentNotPermittedError(required, stamp.consentTier);
	}
	return stamp;
}

export interface ProjectSubjectOptions {
	/** The acting user / system actor for the provenance entry. */
	actorUserId?: string | null;
	/**
	 * The IDENTIFIED user id whose consent gates this projection. When supplied
	 * the pipeline enforces (and stamps) the user's current consent; omit only
	 * for already-consent-checked / system aggregate work.
	 */
	consentUserId?: string | null;
}

/**
 * Project ONE identified user record -> the de-identified layer: upsert the
 * pseudonymous subject and record a TRANSFORM (IDENTIFIED -> DEIDENTIFIED)
 * provenance entry keyed by the PSEUDONYM (never the real user id).
 */
export async function projectSubject(
	record: IdentifiedRecord,
	opts: ProjectSubjectOptions = {},
): Promise<DeidentifiedSubjectRecord> {
	// Consent gate (GTM-523): data only crosses into the de-identified layer when
	// the user's current consent permits it. Checked BEFORE de-identifying so an
	// un-consented record is never even transformed. Stamp the tier+version onto
	// the provenance entry. Default to the record's own user id when not overridden.
	const consentUserId = opts.consentUserId ?? record.userId;
	const consentStamp = await assertConsentForLayer(consentUserId, "DEIDENTIFIED");

	const subject = deidentifySubject(record);

	await prisma.deidentifiedSubject.upsert({
		where: { subjectKey: subject.subjectKey },
		create: {
			subjectKey: subject.subjectKey,
			ageBand: subject.ageBand,
			region: subject.region,
		},
		update: {
			ageBand: subject.ageBand,
			region: subject.region,
		},
	});

	await recordProvenance({
		actorUserId: opts.actorUserId ?? null,
		operation: "TRANSFORM",
		layer: "DEIDENTIFIED",
		sourceLayer: "IDENTIFIED",
		resourceType: "DeidentifiedSubject",
		// Provenance references the PSEUDONYM, never the identified user id.
		resourceId: subject.subjectKey,
		// Consent state on every record (GTM-523): tier + version + resolved-at.
		metadata: { ...consentStamp },
	});

	return subject;
}

/**
 * Project ONE identified event -> the de-identified layer: resolve the subject,
 * write a date-shifted, PHI-free DeidentifiedEvent, and record a TRANSFORM
 * provenance entry. `epoch` is the per-subject de-id origin used to compute the
 * relative dayOffset.
 */
export async function projectEvent(
	event: IdentifiedEvent,
	epoch: Date,
	opts: ProjectSubjectOptions = {},
): Promise<DeidentifiedEventRecord> {
	// Consent gate (GTM-523): enforce + stamp the user's current consent BEFORE
	// the event crosses into (or is even transformed for) the de-identified layer.
	const consentUserId = opts.consentUserId ?? event.userId;
	const consentStamp = await assertConsentForLayer(consentUserId, "DEIDENTIFIED");

	const deid = deidentifyEvent(event, epoch);

	const subject = await prisma.deidentifiedSubject.findUnique({
		where: { subjectKey: deid.subjectKey },
		select: { id: true },
	});
	if (!subject) {
		// The subject must be projected first; fail-closed rather than orphan an
		// event without a subject row.
		throw new Error(
			"projectEvent: subject not found for pseudonym; project the subject first",
		);
	}

	await prisma.deidentifiedEvent.create({
		data: {
			subjectId: subject.id,
			eventType: deid.eventType,
			dayOffset: deid.dayOffset,
			hourBucket: deid.hourBucket,
			value: deid.value,
		},
	});

	await recordProvenance({
		actorUserId: opts.actorUserId ?? null,
		operation: "TRANSFORM",
		layer: "DEIDENTIFIED",
		sourceLayer: "IDENTIFIED",
		resourceType: "DeidentifiedEvent",
		resourceId: deid.subjectKey,
		metadata: { eventType: deid.eventType, ...consentStamp },
	});

	return deid;
}

export interface UpsertMetricInput {
	metric: string;
	cohort?: string | null;
	period: string;
	value: number;
	sampleSize?: number;
	metadata?: Record<string, unknown> | null;
	actorUserId?: string | null;
	/**
	 * Consent gate for the ANALYTIC / sale layer (GTM-523). When supplied, the
	 * user's current consent must permit `requiredTier` (defaults to the layer's
	 * RESEARCH floor; pass COMMERCIAL_AI_TRAINING for commercial/sale uses) or the
	 * metric is NOT written and a ConsentNotPermittedError is thrown.
	 */
	consentUserId?: string | null;
	requiredTier?: ConsentTier;
}

/**
 * Roll a de-identified metric up into the ANALYTIC layer (upsert per
 * metric+cohort+period) and record a TRANSFORM (DEIDENTIFIED -> ANALYTIC)
 * provenance entry. PHI-free by construction.
 *
 * Consent enforcement (GTM-523): when `consentUserId` is supplied, data only
 * crosses into the analytic / sale layer if that user's current consent permits
 * the use (`requiredTier`, default RESEARCH). The resolved consent tier+version
 * is stamped onto the provenance entry.
 */
export async function upsertAnalyticMetric(
	input: UpsertMetricInput,
): Promise<void> {
	// Consent gate for the analytic/sale layer. Resolve+enforce before writing.
	let consentStamp: ConsentStamp | null = null;
	if (input.consentUserId) {
		const { consent, stamp } = await resolveConsentStamp(input.consentUserId);
		const required = input.requiredTier ?? LAYER_REQUIRED_TIER.ANALYTIC;
		if (!isPermitted(consent, required)) {
			throw new ConsentNotPermittedError(required, stamp.consentTier);
		}
		consentStamp = stamp;
	}

	const cohort = input.cohort ?? null;
	const row = await prisma.analyticMetric.upsert({
		where: {
			metric_cohort_period: {
				metric: input.metric,
				cohort,
				period: input.period,
			},
		},
		create: {
			metric: input.metric,
			cohort,
			period: input.period,
			value: input.value,
			sampleSize: input.sampleSize ?? 0,
			metadata: input.metadata ?? undefined,
		},
		update: {
			value: input.value,
			sampleSize: input.sampleSize ?? 0,
			metadata: input.metadata ?? undefined,
		},
	});

	await recordProvenance({
		actorUserId: input.actorUserId ?? null,
		operation: "TRANSFORM",
		layer: "ANALYTIC",
		sourceLayer: "DEIDENTIFIED",
		resourceType: "AnalyticMetric",
		resourceId: row.id,
		metadata: {
			metric: input.metric,
			period: input.period,
			cohort,
			...(consentStamp ?? {}),
		},
	});
}

export const DataPipelineService = {
	projectSubject,
	projectEvent,
	upsertAnalyticMetric,
	resolveConsentStamp,
	assertConsentForLayer,
	LAYER_REQUIRED_TIER,
	ConsentNotPermittedError,
};

export default DataPipelineService;
