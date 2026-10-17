import type { PrismaClient } from "../../generated/prisma/client";
import { ConsumerError } from "../reminders/policy";
import { lock, serial, type Transaction } from "../reminders/service";
import {
	type ApnsAdapter,
	type ApnsResult,
	ApnsTransportError,
	type LiveActivityConfig,
	type LiveActivityPayload,
	liveActivityConfig,
	makeApnsAdapter,
	validateLiveActivityPayload,
} from "./apns";

const INSTALLATION_TTL_MS = 30 * 24 * 60 * 60_000;
const WINDOW_MS = 60 * 60_000;
const END_INTENT_TTL_MS = 15 * 60_000;

export interface InstallationTokenInput {
	installationId: string;
	token: string;
}
export interface ActivityTokenInput extends InstallationTokenInput {
	activityId: string;
	occurrenceId: string;
}

export async function queueLiveActivityEnd(
	tx: Transaction,
	dose: { id: string; userId: string },
	now: Date,
) {
	const expiresAt = new Date(now.getTime() + END_INTENT_TTL_MS);
	await tx.reminderIntent.upsert({
		where: {
			doseId_channel_stage: {
				doseId: dose.id,
				channel: "live_activity",
				stage: "end",
			},
		},
		create: {
			userId: dose.userId,
			doseId: dose.id,
			channel: "live_activity",
			stage: "end",
			dueAt: now,
			expiresAt,
		},
		// Preserve pending work across repeated terminal writes. A legacy cancelled
		// end can be reopened, while a dispatched end remains final.
		update: { dueAt: now, expiresAt },
	});
	await tx.reminderIntent.updateMany({
		where: {
			doseId: dose.id,
			channel: "live_activity",
			stage: "end",
			state: "cancelled",
		},
		data: { state: "pending", reason: null, dueAt: now, expiresAt },
	});
}

export async function revokeLiveActivitySession(
	tx: Transaction,
	userId: string,
	sessionId: string,
	now: Date,
) {
	const installations = await tx.liveActivityInstallation.findMany({
		where: { userId, sessionId },
		select: { installationId: true },
	});
	const installationIds = installations.map(
		(installation) => installation.installationId,
	);
	await tx.liveActivityInstallation.updateMany({
		where: { installationId: { in: installationIds }, revokedAt: null },
		data: { revokedAt: now },
	});
	await tx.liveActivityToken.updateMany({
		where: { installationId: { in: installationIds }, revokedAt: null },
		data: { revokedAt: now },
	});
}

type Eligible = {
	intent: {
		id: string;
		userId: string;
		doseId: string;
		stage: string;
		dueAt: Date;
		expiresAt: Date;
	};
	dose: {
		id: string;
		userId: string;
		scheduledFor: Date;
		takenAt: Date | null;
		canceledAt: Date | null;
		snoozedUntil: Date | null;
		status: string;
		revision: number;
		updatedAt: Date;
	};
};

export class LiveActivityDeliveryService {
	private readonly protector;

	constructor(
		private readonly db: PrismaClient,
		private readonly apns: ApnsAdapter = makeApnsAdapter(),
		private readonly config: LiveActivityConfig = liveActivityConfig(),
		private readonly now: () => Date = () => new Date(),
	) {
		this.protector = config.protector;
	}

	get enabled() {
		return this.config.enabled && this.apns.enabled && this.protector !== null;
	}

	private requireEnabled() {
		if (!this.enabled)
			throw new ConsumerError(
				503,
				"Remote Live Activities are not configured.",
			);
		return this.protector!;
	}

	async readyForUser(userId: string): Promise<boolean> {
		// The authenticated caller is checked by ReminderService. Capability means
		// this deployment can accept and deliver tokens; it never claims a device
		// has registered or that APNs delivered anything.
		void userId;
		return this.enabled;
	}

	async registerInstallation(
		userId: string,
		sessionId: string,
		input: InstallationTokenInput,
	) {
		const protector = this.requireEnabled();
		const now = this.now();
		const fingerprint = protector.fingerprint(input.token);
		const context = `installation:${userId}:${input.installationId}`;
		await serial(this.db, async (tx) => {
			await lock(tx, `live-activity-fingerprint:${fingerprint}`);
			const priorDuplicate = await tx.liveActivityInstallation.findUnique({
				where: { tokenFingerprint: fingerprint },
			});
			for (const id of new Set(
				[input.installationId, priorDuplicate?.installationId]
					.filter((value): value is string => Boolean(value))
					.sort(),
			))
				await lock(tx, `live-activity-installation:${id}`);
			const [preference, installation, duplicate] = await Promise.all([
				tx.reminderPreference.findUnique({ where: { userId } }),
				tx.liveActivityInstallation.findUnique({
					where: { installationId: input.installationId },
				}),
				tx.liveActivityInstallation.findUnique({
					where: { tokenFingerprint: fingerprint },
				}),
			]);
			if (!preference?.liveActivitiesEnabled)
				throw new ConsumerError(
					409,
					"Enable Live Activities before registering this device.",
				);
			if (installation && installation.userId !== userId)
				throw new ConsumerError(409, "This installation cannot be registered.");
			if (
				duplicate &&
				duplicate.installationId !== input.installationId &&
				duplicate.userId === userId &&
				duplicate.sessionId === sessionId &&
				duplicate.revokedAt === null
			)
				throw new ConsumerError(
					409,
					"This device token is already registered by another installation.",
				);
			// Presenting the same opaque APNs credential from a new authenticated
			// session proves possession of the device token. Retire the previous
			// binding before assigning it; an installation ID alone can never do so.
			if (duplicate && duplicate.installationId !== input.installationId) {
				await tx.liveActivityToken.deleteMany({
					where: { installationId: duplicate.installationId },
				});
				await tx.liveActivityInstallation.deleteMany({
					where: { installationId: duplicate.installationId },
				});
			}
			if (
				duplicate?.installationId === input.installationId &&
				duplicate.userId !== userId
			)
				await tx.liveActivityToken.deleteMany({
					where: { installationId: input.installationId },
				});
			const data = {
				userId,
				sessionId,
				tokenFingerprint: fingerprint,
				tokenCiphertext: protector.protect(input.token, context),
				expiresAt: new Date(now.getTime() + INSTALLATION_TTL_MS),
				revokedAt: null,
			};
			await tx.liveActivityInstallation.upsert({
				where: { installationId: input.installationId },
				create: { installationId: input.installationId, ...data },
				update: data,
			});
		});
		return {
			registered: true,
			expiresAt: new Date(now.getTime() + INSTALLATION_TTL_MS),
		};
	}

	async registerActivity(
		userId: string,
		sessionId: string,
		input: ActivityTokenInput,
	) {
		const protector = this.requireEnabled();
		const now = this.now();
		const fingerprint = protector.fingerprint(input.token);
		await serial(this.db, async (tx) => {
			for (const scope of [
				`live-activity-fingerprint:${fingerprint}`,
				`live-activity:${input.activityId}`,
				`live-activity-installation:${input.installationId}`,
			].sort())
				await lock(tx, scope);
			const dose = await tx.dose.findFirst({
				where: { id: input.occurrenceId, userId },
			});
			if (!dose) throw new ConsumerError(404, "Routine entry not found.");
			const expiresAt = new Date(dose.scheduledFor.getTime() + WINDOW_MS);
			if (expiresAt <= now)
				throw new ConsumerError(409, "This reminder window has ended.");
			if (
				dose.takenAt ||
				dose.canceledAt ||
				dose.snoozedUntil ||
				dose.status !== "unconfirmed"
			)
				throw new ConsumerError(409, "This reminder is no longer active.");
			const [preference, installation, activity, duplicate] = await Promise.all(
				[
					tx.reminderPreference.findUnique({ where: { userId } }),
					tx.liveActivityInstallation.findUnique({
						where: { installationId: input.installationId },
					}),
					tx.liveActivityToken.findUnique({
						where: { activityId: input.activityId },
					}),
					tx.liveActivityToken.findUnique({
						where: { tokenFingerprint: fingerprint },
					}),
				],
			);
			if (!preference?.liveActivitiesEnabled)
				throw new ConsumerError(
					409,
					"Enable Live Activities before registering this device.",
				);
			if (
				(installation && installation.userId !== userId) ||
				(activity &&
					(activity.userId !== userId || activity.doseId !== dose.id)) ||
				(duplicate &&
					(duplicate.userId !== userId ||
						duplicate.activityId !== input.activityId))
			)
				throw new ConsumerError(409, "This activity cannot be registered.");
			if (!installation)
				await tx.liveActivityInstallation.create({
					data: { installationId: input.installationId, userId, sessionId },
				});
			else if (installation.sessionId !== sessionId)
				await tx.liveActivityInstallation.update({
					where: { installationId: input.installationId },
					data: { sessionId },
				});
			const context = `activity:${userId}:${input.installationId}:${input.activityId}:${dose.id}`;
			const data = {
				userId,
				installationId: input.installationId,
				doseId: dose.id,
				tokenFingerprint: fingerprint,
				tokenCiphertext: protector.protect(input.token, context),
				expiresAt,
				revokedAt: null,
			};
			await tx.liveActivityToken.upsert({
				where: { activityId: input.activityId },
				create: { activityId: input.activityId, ...data },
				update: data,
			});
		});
		return { registered: true };
	}

	async revokeInstallation(userId: string, installationId: string) {
		const now = this.now();
		await serial(this.db, async (tx) => {
			await lock(tx, `live-activity-installation:${installationId}`);
			await Promise.all([
				tx.liveActivityInstallation.updateMany({
					where: { installationId, userId, revokedAt: null },
					data: { revokedAt: now },
				}),
				tx.liveActivityToken.updateMany({
					where: { installationId, userId, revokedAt: null },
					data: { revokedAt: now },
				}),
			]);
		});
	}

	private async eligibility(
		tx: Transaction,
		intentId: string,
		now: Date,
	): Promise<Eligible | { reason: string }> {
		const intent = await tx.reminderIntent.findUnique({
			where: { id: intentId },
		});
		if (
			!intent ||
			intent.channel !== "live_activity" ||
			intent.state !== "pending"
		)
			return { reason: "intent_unavailable" };
		if (intent.dueAt > now) return { reason: "not_due" };
		if (intent.expiresAt <= now) return { reason: "window_expired" };
		const [dose, preference] = await Promise.all([
			tx.dose.findFirst({
				where: { id: intent.doseId, userId: intent.userId },
			}),
			tx.reminderPreference.findUnique({ where: { userId: intent.userId } }),
		]);
		if (!dose) return { reason: "occurrence_missing" };
		const ending = intent.stage === "end";
		if (ending) {
			if (dose.status !== "taken" && dose.status !== "skipped")
				return { reason: "terminal_state_changed" };
		} else {
			if (
				dose.takenAt ||
				dose.canceledAt ||
				dose.snoozedUntil ||
				dose.status !== "unconfirmed"
			)
				return { reason: "occurrence_resolved" };
			if (!preference?.liveActivitiesEnabled)
				return { reason: "preference_disabled" };
		}
		if (intent.stage === "before" && now >= dose.scheduledFor)
			return { reason: "heads_up_expired" };
		if (intent.stage === "due" && now < dose.scheduledFor)
			return { reason: "not_due" };
		if (
			intent.stage !== "before" &&
			intent.stage !== "due" &&
			intent.stage !== "end"
		)
			return { reason: "stage_invalid" };
		return { intent, dose } as Eligible;
	}

	private payload(eligible: Eligible, now: Date): LiveActivityPayload {
		const before = eligible.intent.stage === "before";
		const ending = eligible.intent.stage === "end";
		const dueAt = Math.floor(eligible.dose.scheduledFor.getTime() / 1000);
		const windowEndsAt = Math.floor(
			(eligible.dose.scheduledFor.getTime() + WINDOW_MS) / 1000,
		);
		const content = {
			phase: ending
				? eligible.dose.status === "taken"
					? "confirmed"
					: "cancelled"
				: before
					? "headsUp"
					: "due",
			revision: eligible.dose.revision,
			dueAt,
			windowEndsAt,
			updatedAt: Math.floor(eligible.dose.updatedAt.getTime() / 1000),
		};
		return {
			aps: {
				timestamp: Math.floor(now.getTime() / 1000),
				event: ending ? "end" : before ? "start" : "update",
				"content-state": content,
				...(ending
					? {
							"dismissal-date":
								Math.floor(now.getTime() / 1000) +
								(eligible.dose.status === "taken" ? 60 : 0),
						}
					: { "stale-date": before ? dueAt : windowEndsAt }),
				...(before
					? {
							"attributes-type": "FardaRoutineAttributes" as const,
							"input-push-token": 1 as const,
							attributes: { occurrenceId: eligible.dose.id },
							alert: {
								title: "A little heads-up.",
								body: "Your routine is coming up.",
							},
						}
					: ending
						? {}
						: {
								alert: {
									title: "Your routine is ready.",
									body: "Open Farda to check in.",
								},
							}),
			},
		};
	}

	private async closeIntentFromAttempts(
		tx: Transaction,
		intentId: string,
		failureReason: string,
	) {
		const attempts = await tx.liveActivityAttempt.findMany({
			where: { intentId },
			select: { state: true },
		});
		if (
			attempts.some((attempt) =>
				["reserved", "dispatching"].includes(attempt.state),
			)
		)
			return;
		const ambiguousOrSubmitted = attempts.some((attempt) =>
			["submitted", "uncertain"].includes(attempt.state),
		);
		await tx.reminderIntent.updateMany({
			where: { id: intentId, state: "pending" },
			data: ambiguousOrSubmitted
				? { state: "dispatched", reason: null }
				: { state: "cancelled", reason: failureReason },
		});
	}

	private async revokeExpiredSessionTargets(tx: Transaction, now: Date) {
		await tx.liveActivityToken.updateMany({
			where: {
				revokedAt: null,
				installation: { session: { expiresAt: { lte: now } } },
			},
			data: { revokedAt: now },
		});
		await tx.liveActivityInstallation.updateMany({
			where: { revokedAt: null, session: { expiresAt: { lte: now } } },
			data: { revokedAt: now },
		});
	}

	private async finishAttempt(input: {
		attemptId: string;
		intentId: string;
		userId: string;
		fingerprint: string;
		kind: "installation" | "activity";
		state: string;
		reason: string | null;
		providerStatus?: string;
		retireToken: boolean;
		expectedState?: "reserved" | "dispatching";
	}) {
		await serial(this.db, async (tx) => {
			await lock(tx, `live-activity-intent:${input.intentId}`);
			await tx.liveActivityAttempt.updateMany({
				where: {
					id: input.attemptId,
					state: input.expectedState || "dispatching",
				},
				data: {
					state: input.state,
					reason: input.reason,
					...(input.providerStatus
						? { providerStatus: input.providerStatus }
						: {}),
				},
			});
			if (input.retireToken) {
				const table =
					input.kind === "installation"
						? tx.liveActivityInstallation
						: tx.liveActivityToken;
				await (table as typeof tx.liveActivityToken).updateMany({
					where: {
						userId: input.userId,
						tokenFingerprint: input.fingerprint,
					},
					data: { revokedAt: this.now() },
				});
			}
			await this.closeIntentFromAttempts(
				tx,
				input.intentId,
				input.reason || "live_activity_not_submitted",
			);
		});
	}

	async dispatch(intentId: string, now = this.now()) {
		if (!this.enabled) return { state: "disabled" as const };
		const reservations = await serial(this.db, async (tx) => {
			await lock(tx, `live-activity-intent:${intentId}`);
			await this.revokeExpiredSessionTargets(tx, now);
			const eligible = await this.eligibility(tx, intentId, now);
			if ("reason" in eligible) {
				if (
					eligible.reason !== "not_due" &&
					eligible.reason !== "intent_unavailable"
				)
					await tx.reminderIntent.updateMany({
						where: { id: intentId, state: "pending" },
						data: { state: "cancelled", reason: eligible.reason },
					});
				return [];
			}
			const before = eligible.intent.stage === "before";
			const targets = before
				? await tx.liveActivityInstallation.findMany({
						where: {
							userId: eligible.intent.userId,
							revokedAt: null,
							tokenCiphertext: { not: null },
							tokenFingerprint: { not: null },
							expiresAt: { gt: now },
							session: { expiresAt: { gt: now } },
						},
					})
				: await tx.liveActivityToken.findMany({
						where: {
							userId: eligible.intent.userId,
							doseId: eligible.intent.doseId,
							revokedAt: null,
							expiresAt: { gt: now },
							installation: {
								revokedAt: null,
								session: { expiresAt: { gt: now } },
							},
						},
					});
			const result = [];
			for (const target of targets) {
				if (!target.tokenFingerprint || !target.tokenCiphertext) continue;
				const existing = await tx.liveActivityAttempt.findUnique({
					where: {
						intentId_targetFingerprint: {
							intentId,
							targetFingerprint: target.tokenFingerprint,
						},
					},
				});
				if (existing) continue;
				const attempt = await tx.liveActivityAttempt.create({
					data: {
						intentId,
						userId: eligible.intent.userId,
						targetFingerprint: target.tokenFingerprint,
						targetKind: before ? "push_to_start" : "activity",
					},
				});
				const activityTarget = target as typeof target & {
					activityId: string;
					doseId: string;
				};
				result.push({
					attemptId: attempt.id,
					fingerprint: target.tokenFingerprint,
					ciphertext: target.tokenCiphertext,
					context:
						"activityId" in target
							? `activity:${target.userId}:${target.installationId}:${activityTarget.activityId}:${activityTarget.doseId}`
							: `installation:${target.userId}:${target.installationId}`,
					kind: before ? ("installation" as const) : ("activity" as const),
					ending: eligible.intent.stage === "end",
				});
			}
			if (result.length === 0)
				await this.closeIntentFromAttempts(
					tx,
					intentId,
					targets.length === 0
						? "no_live_activity_target"
						: "live_activity_already_attempted",
				);
			return result;
		});
		if (reservations.length === 0) return { state: "suppressed" as const };
		let submitted = 0;
		let uncertain = 0;
		for (const reservation of reservations) {
			const candidate = await serial(this.db, async (tx) => {
				await lock(tx, `live-activity-intent:${intentId}`);
				const eligible = await this.eligibility(tx, intentId, this.now());
				const attempt = await tx.liveActivityAttempt.findUnique({
					where: { id: reservation.attemptId },
				});
				if ("reason" in eligible || attempt?.state !== "reserved") {
					await tx.liveActivityAttempt.updateMany({
						where: { id: reservation.attemptId, state: "reserved" },
						data: { state: "cancelled", reason: "dispatch_recheck" },
					});
					await this.closeIntentFromAttempts(tx, intentId, "dispatch_recheck");
					return null;
				}
				return eligible;
			});
			if (!candidate) continue;
			let token: string;
			try {
				token = this.protector!.unprotect(
					reservation.ciphertext,
					reservation.context,
				);
				if (!this.protector!.matches(token, reservation.fingerprint))
					throw new Error("live_activity_token_mismatch");
				validateLiveActivityPayload(this.payload(candidate, this.now()));
			} catch (error) {
				await this.finishAttempt({
					attemptId: reservation.attemptId,
					intentId,
					userId: candidate.intent.userId,
					fingerprint: reservation.fingerprint,
					kind: reservation.kind,
					state: "failed",
					reason:
						error instanceof Error &&
						error.message === "live_activity_token_mismatch"
							? "local_token_mismatch"
							: "local_token_unreadable",
					retireToken: true,
					expectedState: "reserved",
				});
				continue;
			}
			const ready = await serial(this.db, async (tx) => {
				await lock(tx, `live-activity-intent:${intentId}`);
				const eligible = await this.eligibility(tx, intentId, this.now());
				const attempt = await tx.liveActivityAttempt.findUnique({
					where: { id: reservation.attemptId },
				});
				if ("reason" in eligible || attempt?.state !== "reserved") {
					await tx.liveActivityAttempt.updateMany({
						where: { id: reservation.attemptId, state: "reserved" },
						data: { state: "cancelled", reason: "dispatch_recheck" },
					});
					await this.closeIntentFromAttempts(tx, intentId, "dispatch_recheck");
					return null;
				}
				await tx.liveActivityAttempt.update({
					where: { id: reservation.attemptId },
					data: { state: "dispatching", startedAt: this.now() },
				});
				return eligible;
			});
			if (!ready) continue;
			const payload: LiveActivityPayload = this.payload(ready, this.now());
			let result: ApnsResult;
			try {
				result = await this.apns.send(token, payload, ready.intent.expiresAt);
			} catch (error) {
				const transportUnknown = error instanceof ApnsTransportError;
				if (transportUnknown) uncertain++;
				await this.finishAttempt({
					attemptId: reservation.attemptId,
					intentId,
					userId: ready.intent.userId,
					fingerprint: reservation.fingerprint,
					kind: reservation.kind,
					state: transportUnknown ? "uncertain" : "failed",
					reason: transportUnknown
						? "provider_result_unknown"
						: "local_apns_failure",
					retireToken: reservation.ending || !transportUnknown,
				});
				continue;
			}
			try {
				await this.finishAttempt({
					attemptId: reservation.attemptId,
					intentId,
					userId: ready.intent.userId,
					fingerprint: reservation.fingerprint,
					kind: reservation.kind,
					state: result.accepted ? "submitted" : "rejected",
					providerStatus: String(result.status),
					reason: result.accepted ? null : result.reason || "provider_rejected",
					retireToken: reservation.ending || result.invalidateToken,
				});
				if (result.accepted) submitted++;
			} catch {
				// APNs has already returned. Keep the durable attempt dispatching so the
				// stale-attempt sweep records ambiguity; never relabel it as unsent.
				uncertain++;
			}
		}
		return {
			state:
				uncertain > 0
					? ("uncertain" as const)
					: submitted > 0
						? ("submitted" as const)
						: ("cancelled" as const),
			submitted,
			uncertain,
		};
	}

	async tick(now = this.now()) {
		await serial(this.db, (tx) => this.revokeExpiredSessionTargets(tx, now));
		await Promise.all([
			this.db.liveActivityInstallation.updateMany({
				where: { revokedAt: null, expiresAt: { lte: now } },
				data: { revokedAt: now },
			}),
			this.db.liveActivityToken.updateMany({
				where: { revokedAt: null, expiresAt: { lte: now } },
				data: { revokedAt: now },
			}),
			this.db.reminderIntent.updateMany({
				where: {
					channel: "live_activity",
					state: "pending",
					expiresAt: { lte: now },
				},
				data: { state: "cancelled", reason: "window_expired" },
			}),
		]);
		await serial(this.db, async (tx) => {
			const stale = await tx.liveActivityAttempt.findMany({
				where: {
					state: { in: ["reserved", "dispatching"] },
					updatedAt: { lt: new Date(now.getTime() - 2 * 60_000) },
				},
			});
			for (const attempt of stale) {
				const ambiguous = attempt.state === "dispatching";
				await tx.liveActivityAttempt.updateMany({
					where: { id: attempt.id, state: attempt.state },
					data: {
						state: ambiguous ? "uncertain" : "failed",
						reason: ambiguous
							? "provider_result_unknown"
							: "worker_interrupted_before_send",
					},
				});
			}
			for (const intentId of new Set(stale.map((attempt) => attempt.intentId)))
				await this.closeIntentFromAttempts(
					tx,
					intentId,
					"worker_interrupted_before_send",
				);
		});
		if (!this.enabled) return;
		const intents = await this.db.reminderIntent.findMany({
			where: {
				channel: "live_activity",
				state: "pending",
				dueAt: { lte: now },
				expiresAt: { gt: now },
			},
			take: 100,
			orderBy: { dueAt: "asc" },
		});
		for (const intent of intents) await this.dispatch(intent.id, now);
	}
}
