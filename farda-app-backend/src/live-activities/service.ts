import type { PrismaClient } from "../../generated/prisma/client";
import { ConsumerError } from "../reminders/policy";
import { lock, serial, type Transaction } from "../reminders/service";
import {
	type ApnsAdapter,
	type LiveActivityConfig,
	type LiveActivityPayload,
	liveActivityConfig,
	makeApnsAdapter,
} from "./apns";

const INSTALLATION_TTL_MS = 30 * 24 * 60 * 60_000;
const WINDOW_MS = 60 * 60_000;

export interface InstallationTokenInput {
	installationId: string;
	token: string;
}
export interface ActivityTokenInput extends InstallationTokenInput {
	activityId: string;
	occurrenceId: string;
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

	async registerInstallation(userId: string, input: InstallationTokenInput) {
		const protector = this.requireEnabled();
		const now = this.now();
		const fingerprint = protector.fingerprint(input.token);
		const context = `installation:${userId}:${input.installationId}`;
		await serial(this.db, async (tx) => {
			await lock(tx, `live-activity-installation:${input.installationId}`);
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
			if (
				(installation && installation.userId !== userId) ||
				(duplicate &&
					(duplicate.userId !== userId ||
						duplicate.installationId !== input.installationId))
			)
				throw new ConsumerError(409, "This installation cannot be registered.");
			const data = {
				userId,
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

	async registerActivity(userId: string, input: ActivityTokenInput) {
		const protector = this.requireEnabled();
		const now = this.now();
		const fingerprint = protector.fingerprint(input.token);
		await serial(this.db, async (tx) => {
			await lock(tx, `live-activity:${input.activityId}`);
			const dose = await tx.dose.findFirst({
				where: { id: input.occurrenceId, userId },
			});
			if (!dose) throw new ConsumerError(404, "Routine entry not found.");
			const expiresAt = new Date(dose.scheduledFor.getTime() + WINDOW_MS);
			if (expiresAt <= now)
				throw new ConsumerError(409, "This reminder window has ended.");
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
					data: { installationId: input.installationId, userId },
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
		if (
			dose.takenAt ||
			dose.canceledAt ||
			dose.snoozedUntil ||
			dose.status !== "unconfirmed"
		)
			return { reason: "occurrence_resolved" };
		if (!preference?.liveActivitiesEnabled)
			return { reason: "preference_disabled" };
		if (intent.stage === "before" && now >= dose.scheduledFor)
			return { reason: "heads_up_expired" };
		if (intent.stage === "due" && now < dose.scheduledFor)
			return { reason: "not_due" };
		if (intent.stage !== "before" && intent.stage !== "due")
			return { reason: "stage_invalid" };
		return { intent, dose } as Eligible;
	}

	private payload(eligible: Eligible, now: Date): LiveActivityPayload {
		const before = eligible.intent.stage === "before";
		const dueAt = Math.floor(eligible.dose.scheduledFor.getTime() / 1000);
		const windowEndsAt = Math.floor(
			(eligible.dose.scheduledFor.getTime() + WINDOW_MS) / 1000,
		);
		const content = {
			phase: before ? "headsUp" : "due",
			revision: eligible.dose.revision,
			dueAt,
			windowEndsAt,
			updatedAt: Math.floor(eligible.dose.updatedAt.getTime() / 1000),
		};
		return {
			aps: {
				timestamp: Math.floor(now.getTime() / 1000),
				event: before ? "start" : "update",
				"content-state": content,
				"stale-date": before ? dueAt : windowEndsAt,
				...(before
					? {
							"attributes-type": "FardaRoutineAttributes" as const,
							attributes: { occurrenceId: eligible.dose.id },
							alert: {
								title: "A little heads-up.",
								body: "Your routine is coming up.",
							},
						}
					: {
							alert: {
								title: "Your routine is ready.",
								body: "Open Farda to check in.",
							},
						}),
			},
		};
	}

	async dispatch(intentId: string, now = this.now()) {
		if (!this.enabled) return { state: "disabled" as const };
		const reservations = await serial(this.db, async (tx) => {
			await lock(tx, `live-activity-intent:${intentId}`);
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
						},
					})
				: await tx.liveActivityToken.findMany({
						where: {
							userId: eligible.intent.userId,
							doseId: eligible.intent.doseId,
							revokedAt: null,
							expiresAt: { gt: now },
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
					kind: before ? "installation" : "activity",
				});
			}
			return result;
		});
		if (reservations.length === 0) return { state: "suppressed" as const };
		let submitted = 0;
		let uncertain = 0;
		for (const reservation of reservations) {
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
					return null;
				}
				await tx.liveActivityAttempt.update({
					where: { id: reservation.attemptId },
					data: { state: "dispatching", startedAt: this.now() },
				});
				return eligible;
			});
			if (!ready) continue;
			try {
				const token = this.protector!.unprotect(
					reservation.ciphertext,
					reservation.context,
				);
				if (!this.protector!.matches(token, reservation.fingerprint))
					throw new Error("live_activity_token_mismatch");
				const result = await this.apns.send(
					token,
					this.payload(ready, this.now()),
					ready.intent.expiresAt,
				);
				await serial(this.db, async (tx) => {
					await tx.liveActivityAttempt.update({
						where: { id: reservation.attemptId },
						data: {
							state: result.accepted ? "submitted" : "rejected",
							providerStatus: String(result.status),
							reason: result.accepted
								? null
								: result.reason || "provider_rejected",
						},
					});
					if (result.invalidateToken) {
						const table =
							reservation.kind === "installation"
								? tx.liveActivityInstallation
								: tx.liveActivityToken;
						await (table as typeof tx.liveActivityToken).updateMany({
							where: {
								userId: ready.intent.userId,
								tokenFingerprint: reservation.fingerprint,
							},
							data: { revokedAt: this.now() },
						});
					}
				});
				if (result.accepted) submitted++;
			} catch {
				uncertain++;
				await this.db.liveActivityAttempt.updateMany({
					where: { id: reservation.attemptId, state: "dispatching" },
					data: { state: "uncertain", reason: "provider_result_unknown" },
				});
			}
		}
		if (submitted > 0 || uncertain > 0)
			await this.db.reminderIntent.updateMany({
				where: { id: intentId, state: "pending" },
				data: { state: "dispatched" },
			});
		else
			await this.db.reminderIntent.updateMany({
				where: { id: intentId, state: "pending" },
				data: { state: "cancelled", reason: "live_activity_not_submitted" },
			});
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
		await Promise.all([
			this.db.liveActivityInstallation.updateMany({
				where: { revokedAt: null, expiresAt: { lte: now } },
				data: { revokedAt: now },
			}),
			this.db.liveActivityToken.updateMany({
				where: { revokedAt: null, expiresAt: { lte: now } },
				data: { revokedAt: now },
			}),
			this.db.liveActivityAttempt.updateMany({
				where: {
					state: { in: ["reserved", "dispatching"] },
					updatedAt: { lt: new Date(now.getTime() - 2 * 60_000) },
				},
				data: { state: "uncertain", reason: "worker_interrupted" },
			}),
		]);
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
