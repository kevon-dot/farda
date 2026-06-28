import { prisma } from "@src/lib/prisma";
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

export interface ProjectSubjectOptions {
	/** The acting user / system actor for the provenance entry. */
	actorUserId?: string | null;
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
		metadata: { eventType: deid.eventType },
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
}

/**
 * Roll a de-identified metric up into the ANALYTIC layer (upsert per
 * metric+cohort+period) and record a TRANSFORM (DEIDENTIFIED -> ANALYTIC)
 * provenance entry. PHI-free by construction.
 */
export async function upsertAnalyticMetric(
	input: UpsertMetricInput,
): Promise<void> {
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
		metadata: { metric: input.metric, period: input.period, cohort },
	});
}

export const DataPipelineService = {
	projectSubject,
	projectEvent,
	upsertAnalyticMetric,
};

export default DataPipelineService;
