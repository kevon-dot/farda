import type { Prisma, PrismaClient } from "../../generated/prisma/client";
import {
	acceptProviderEvent,
	CADENCE,
	ConsumerError,
	DEFAULT_PREFERENCE,
	inQuietHours,
	localDay,
	type Occurrence,
	occurrenceBlock,
	type Preference,
	reminderPlan,
	reminderWindowState,
	VOICE_CONSENT_TEXT,
	VOICE_CONSENT_VERSION,
} from "./policy";
import { type VoiceAdapter, type VoiceConfig, voiceConfig } from "./voice";

export type Transaction = Prisma.TransactionClient;
const WORKER_LIMITS = Object.freeze({
	planOccurrences: 500,
	dueCalls: 20,
	staleAttempts: 20,
	activeCalls: 20,
	providerConcurrency: 4,
});
const MAX_CANCEL_ATTEMPTS = 3;
const CANCEL_REQUESTED = "cancel_requested";
const CANCEL_RESULT_UNKNOWN = "cancel_result_unknown";
type ReminderEvent =
	| {
			event: "reminder_tick";
			plannedOccurrences: number;
			createdIntents: number;
			expiredIntents: number;
			recoveredReservations: number;
			uncertainDispatches: number;
			dueCalls: number;
			submittedCalls: number;
			suppressedCalls: number;
			cancelRequests: number;
			cancelRetries: number;
			cancelUncertain: number;
			durationMs: number;
	  }
	| { event: "voice_dispatch_uncertain"; count: 1 };
export type ReminderObserver = (event: ReminderEvent) => void;
const defaultObserver: ReminderObserver = (event) => {
	console.info(JSON.stringify(event));
};

async function mapWithConcurrency<T>(
	items: T[],
	concurrency: number,
	work: (item: T) => Promise<void>,
) {
	let cursor = 0;
	await Promise.all(
		Array.from({ length: Math.min(concurrency, items.length) }, async () => {
			while (cursor < items.length) {
				const item = items[cursor++];
				await work(item);
			}
		}),
	);
}
function cancellationAttempts(reason: string | null) {
	const match = /^cancel_retry_(\d+)$/.exec(reason || "");
	return match ? Number(match[1]) : 0;
}
export async function serial<T>(
	db: PrismaClient,
	work: (tx: Transaction) => Promise<T>,
): Promise<T> {
	for (let attempt = 0; ; attempt++) {
		try {
			return await db.$transaction(work, {
				isolationLevel: "Serializable",
				maxWait: 5000,
				timeout: 10000,
			});
		} catch (error) {
			if (attempt >= 3 || error?.code !== "P2034") throw error;
		}
	}
}
export async function lock(tx: Transaction, scope: string) {
	// Prisma's pg adapter cannot deserialize PostgreSQL void; cast the function
	// result while retaining the transaction-scoped advisory lock side effect.
	await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended(${scope}, 0))::text AS acquired`;
}

// Read-only display policy shared by app and APNs payloads. This is a planned
// time, not a delivery promise: dispatch performs the atomic final rechecks.
export async function plannedCallAt(
	tx: Transaction,
	dose: Occurrence,
	now: Date,
	config: VoiceConfig,
): Promise<Date | null> {
	if (!config.enabled || occurrenceBlock(dose, now)) return null;
	const [preference, user, intent] = await Promise.all([
		tx.reminderPreference.findUnique({ where: { userId: dose.userId } }),
		tx.user.findUnique({ where: { id: dose.userId } }),
		tx.reminderIntent.findFirst({
			where: {
				doseId: dose.id,
				userId: dose.userId,
				channel: "voice",
				stage: "follow_up",
				state: "pending",
				expiresAt: { gt: now },
			},
		}),
	]);
	if (
		!intent ||
		!preference?.callsEnabled ||
		!user?.phoneNumberVerified ||
		!user.phoneNumber ||
		!config.allowedPrefixes.some((prefix) =>
			user.phoneNumber!.startsWith(prefix),
		)
	)
		return null;
	if (inQuietHours(intent.dueAt, preference)) return null;
	const consent = await tx.channelConsent.findFirst({
		where: {
			userId: dose.userId,
			channel: "voice",
			phoneNumber: user.phoneNumber,
			wordingVersion: VOICE_CONSENT_VERSION,
			withdrawnAt: null,
		},
	});
	if (!consent) return null;
	const [recent, hourly] = await Promise.all([
		tx.deliveryAttempt.findMany({
			where: {
				userId: dose.userId,
				channel: "voice",
				createdAt: { gte: new Date(now.getTime() - 48 * 60 * 60_000) },
			},
			select: { createdAt: true },
		}),
		tx.deliveryAttempt.count({
			where: {
				channel: "voice",
				createdAt: { gte: new Date(now.getTime() - 60 * 60_000) },
			},
		}),
	]);
	const daily = recent.filter(
		(attempt) =>
			localDay(attempt.createdAt, preference.timeZone) ===
			localDay(intent.dueAt, preference.timeZone),
	).length;
	if (
		daily >= Math.min(preference.maxCallsPerDay, 2) ||
		hourly >= config.maxCallsPerHour
	)
		return null;
	return intent.dueAt;
}
export async function cancelOccurrenceReminders(
	tx: Transaction,
	doseId: string | string[],
	reason: string,
) {
	const doseIds = Array.isArray(doseId) ? doseId : [doseId];
	if (doseIds.length === 0) return;
	const intents = await tx.reminderIntent.findMany({
		where: { doseId: { in: doseIds } },
		select: { id: true },
	});
	await tx.reminderIntent.updateMany({
		where: {
			doseId: { in: doseIds },
			state: { in: ["pending", "reserved", "dispatched"] },
		},
		data: { state: "cancelled", reason },
	});
	await tx.deliveryAttempt.updateMany({
		where: {
			intentId: { in: intents.map((i) => i.id) },
			state: { in: ["reserved", "retryable"] },
		},
		data: { state: "cancelled", reason },
	});
}
async function withdrawCalls(tx: Transaction, userId: string, now: Date) {
	await tx.reminderPreference.upsert({
		where: { userId },
		create: { userId, callsEnabled: false },
		update: { callsEnabled: false },
	});
	await tx.channelConsent.updateMany({
		where: { userId, channel: "voice", withdrawnAt: null },
		data: { withdrawnAt: now },
	});
	await tx.reminderIntent.updateMany({
		where: {
			userId,
			channel: "voice",
			state: { in: ["pending", "reserved", "dispatched"] },
		},
		data: { state: "cancelled", reason: "consent_withdrawn" },
	});
	await tx.deliveryAttempt.updateMany({
		where: {
			userId,
			channel: "voice",
			state: { in: ["reserved", "retryable"] },
		},
		data: { state: "cancelled", reason: "consent_withdrawn" },
	});
}

export class ReminderService {
	constructor(
		private db: PrismaClient,
		private voice: VoiceAdapter,
		private config: VoiceConfig = voiceConfig(),
		private liveActivityReadyForUser: (
			userId: string,
		) => Promise<boolean> = async () => false,
		private observe: ReminderObserver = defaultObserver,
	) {}
	private emit(event: ReminderEvent) {
		try {
			this.observe(event);
		} catch {
			/* Observability must not change reminder delivery state. */
		}
	}

	private async ensurePlans(
		doses: Array<Pick<Occurrence, "id" | "userId" | "scheduledFor">>,
	) {
		if (!doses.length) return 0;
		const data = doses.flatMap((dose) =>
			reminderPlan(dose).map((plan) => ({
				userId: dose.userId,
				doseId: dose.id,
				...plan,
				...(plan.channel === "voice"
					? { expiresAt: new Date(plan.dueAt.getTime() + 5 * 60_000) }
					: {}),
			})),
		);
		const result = await this.db.reminderIntent.createMany({
			data,
			skipDuplicates: true,
		});
		return result.count;
	}

	async preferences(userId: string) {
		const [preference, user] = await Promise.all([
			this.db.reminderPreference.findUnique({ where: { userId } }),
			this.db.user.findUnique({
				where: { id: userId },
				select: { phoneNumber: true, phoneNumberVerified: true },
			}),
		]);
		if (!user) throw new ConsumerError(404, "Account not found.");
		return {
			preferences: preference || DEFAULT_PREFERENCE,
			phoneVerified: !!user.phoneNumber && user.phoneNumberVerified,
			capabilities: {
				voiceEnabled:
					this.voice.enabled &&
					(!user.phoneNumber ||
						this.config.allowedPrefixes.some((prefix) =>
							user.phoneNumber!.startsWith(prefix),
						)),
				liveActivityDeliveryEnabled:
					await this.liveActivityReadyForUser(userId),
			},
			consent: {
				wordingVersion: VOICE_CONSENT_VERSION,
				text: VOICE_CONSENT_TEXT,
			},
			cadence: CADENCE,
		};
	}

	async savePreferences(
		userId: string,
		input: Omit<Preference, "maxCallsPerDay"> & {
			callConsent?: boolean;
			consentVersion?: string;
		},
	) {
		const now = new Date();
		await serial(this.db, async (tx) => {
			await lock(tx, `reminder:${userId}`);
			const user = await tx.user.findUnique({ where: { id: userId } });
			if (!user) throw new ConsumerError(404, "Account not found.");
			const previous = await tx.reminderPreference.findUnique({
				where: { userId },
			});
			const consent = await tx.channelConsent.findFirst({
				where: {
					userId,
					channel: "voice",
					withdrawnAt: null,
					phoneNumber: user.phoneNumber || "",
					wordingVersion: VOICE_CONSENT_VERSION,
				},
			});
			if (input.callsEnabled) {
				if (
					!user.phoneNumberVerified ||
					!user.phoneNumber ||
					!/^\+[1-9]\d{7,14}$/.test(user.phoneNumber)
				)
					throw new ConsumerError(
						409,
						"Verify your phone number before enabling calls.",
					);
				if (
					(!previous?.callsEnabled || !consent) &&
					(!this.voice.enabled ||
						!this.config.allowedPrefixes.some((prefix) =>
							user.phoneNumber!.startsWith(prefix),
						))
				)
					throw new ConsumerError(
						409,
						"Reminder calling is not available for this account yet.",
					);
				if (
					!consent &&
					(input.callConsent !== true ||
						input.consentVersion !== VOICE_CONSENT_VERSION)
				)
					throw new ConsumerError(
						409,
						"Please review and agree to reminder calls.",
					);
				if (!consent) {
					await tx.channelConsent.updateMany({
						where: { userId, channel: "voice", withdrawnAt: null },
						data: { withdrawnAt: now },
					});
					await tx.channelConsent.create({
						data: {
							userId,
							phoneNumber: user.phoneNumber,
							wordingVersion: VOICE_CONSENT_VERSION,
						},
					});
				}
			} else await withdrawCalls(tx, userId, now);
			const {
				callConsent: _consent,
				consentVersion: _version,
				...data
			} = input;
			await tx.reminderPreference.upsert({
				where: { userId },
				create: { userId, ...data },
				update: data,
			});
			if (!input.liveActivitiesEnabled)
				await tx.reminderIntent.updateMany({
					where: { userId, channel: "live_activity", state: "pending" },
					data: { state: "cancelled", reason: "preference_disabled" },
				});
		});
		return this.preferences(userId);
	}

	async plan(userId: string, doseId: string) {
		const dose = (await this.db.dose.findFirst({
			where: { id: doseId, userId },
		})) as Occurrence | null;
		if (!dose) throw new ConsumerError(404, "Routine entry not found.");
		if (!occurrenceBlock(dose, new Date())) {
			// Create once: cancelling or changing a preference never resurrects an old call.
			await this.ensurePlans([dose]);
		}
		return this.occurrence(userId, doseId);
	}

	async occurrence(userId: string, doseId: string) {
		const now = new Date();
		const dose = (await this.db.dose.findFirst({
			where: { id: doseId, userId },
		})) as Occurrence | null;
		if (!dose) throw new ConsumerError(404, "Routine entry not found.");
		const intents = await this.db.reminderIntent.findMany({
			where: { doseId, userId },
			orderBy: { dueAt: "asc" },
			select: {
				id: true,
				channel: true,
				stage: true,
				dueAt: true,
				expiresAt: true,
				state: true,
				reason: true,
				attempt: {
					select: {
						state: true,
						providerStatus: true,
						reason: true,
						updatedAt: true,
					},
				},
			},
		});
		const callAt = this.voice.enabled
			? await plannedCallAt(this.db, dose, now, this.config)
			: null;
		return {
			occurrenceId: dose.id,
			scheduledFor: dose.scheduledFor,
			reminderState: reminderWindowState(dose, now),
			status: dose.status || (dose.takenAt ? "taken" : "unconfirmed"),
			takenAt: dose.takenAt,
			snoozedUntil: dose.snoozedUntil,
			updatedAt: dose.updatedAt,
			revision: dose.revision || 0,
			windowEndsAt: new Date(
				dose.scheduledFor.getTime() + CADENCE.windowMinutes * 60_000,
			),
			callAt,
			intents,
			cadence: CADENCE,
		};
	}

	async snooze(
		userId: string,
		doseId: string,
		minutes: number,
		revision?: number,
	) {
		await serial(this.db, async (tx) => {
			await lock(tx, `reminder:${userId}`);
			const dose = (await tx.dose.findFirst({
				where: { id: doseId, userId },
			})) as Occurrence | null;
			if (!dose) throw new ConsumerError(404, "Routine entry not found.");
			if (
				dose.takenAt ||
				dose.canceledAt ||
				(dose.status && dose.status !== "unconfirmed")
			)
				throw new ConsumerError(
					409,
					"This routine entry has already been resolved.",
				);
			if (revision !== undefined && revision !== (dose.revision || 0))
				throw new ConsumerError(
					409,
					"This routine changed. Refresh before snoozing.",
				);
			const until = new Date(Date.now() + minutes * 60_000);
			if (
				until.getTime() >
					dose.scheduledFor.getTime() + CADENCE.windowMinutes * 60_000 ||
				Date.now() <
					dose.scheduledFor.getTime() - CADENCE.beforeMinutes * 60_000
			)
				throw new ConsumerError(
					409,
					"Snooze is available during the active reminder window.",
				);
			// revision is provided by the canonical occurrence migration. The cast keeps
			// this additive module compatible while that migration is cherry-picked.
			await tx.dose.update({
				where: { id: doseId },
				data: {
					snoozedUntil: until,
					revision: { increment: 1 },
				} as Prisma.DoseUpdateInput,
			});
			// The canonical core migration supplies the shared audit table. Keeping
			// snooze in that same revision stream makes concurrent corrections visible.
			const audit = tx as Transaction & {
				doseCorrection: {
					create(args: { data: Record<string, unknown> }): Promise<unknown>;
				};
			};
			await audit.doseCorrection.create({
				data: {
					doseId,
					actorId: userId,
					revision: (dose.revision || 0) + 1,
					before: { snoozedUntil: dose.snoozedUntil?.toISOString() || null },
					after: { snoozedUntil: until.toISOString() },
					reason: "user_snoozed",
				},
			});
			await cancelOccurrenceReminders(tx, doseId, "user_snoozed");
		});
		return this.occurrence(userId, doseId);
	}

	private async eligibility(tx: Transaction, intentId: string, now: Date) {
		const intent = await tx.reminderIntent.findUnique({
			where: { id: intentId },
		});
		if (!intent || intent.channel !== "voice" || intent.state === "cancelled")
			return { reason: "intent_cancelled" } as const;
		if (intent.dueAt > now) return { reason: "not_due" } as const;
		if (intent.expiresAt <= now) return { reason: "window_expired" } as const;
		const [dose, preference, user] = await Promise.all([
			tx.dose.findFirst({
				where: { id: intent.doseId, userId: intent.userId },
			}),
			tx.reminderPreference.findUnique({ where: { userId: intent.userId } }),
			tx.user.findUnique({ where: { id: intent.userId } }),
		]);
		const reason = occurrenceBlock(dose as Occurrence | null, now);
		if (reason) return { reason } as const;
		if (
			!preference?.callsEnabled ||
			!user?.phoneNumberVerified ||
			!user.phoneNumber
		)
			return { reason: "calls_not_authorized" } as const;
		const consent = await tx.channelConsent.findFirst({
			where: {
				userId: intent.userId,
				channel: "voice",
				phoneNumber: user.phoneNumber,
				withdrawnAt: null,
				wordingVersion: VOICE_CONSENT_VERSION,
			},
		});
		if (!consent) return { reason: "consent_missing" } as const;
		if (
			!this.config.allowedPrefixes.some((prefix) =>
				user.phoneNumber!.startsWith(prefix),
			)
		)
			return { reason: "country_unavailable" } as const;
		if (inQuietHours(now, preference))
			return { reason: "quiet_hours" } as const;
		return { intent, user, preference } as const;
	}

	async dispatch(intentId: string, now = new Date()) {
		if (!this.voice.enabled) return { state: "disabled" };
		const attempt = await serial(this.db, async (tx) => {
			// Global and account locks serialize caps; unique intentId protects races
			// even across worker processes. Serializable retries rerun fresh reads.
			await lock(tx, "voice-budget");
			const intent = await tx.reminderIntent.findUnique({
				where: { id: intentId },
			});
			if (!intent || intent.state !== "pending") return null;
			await lock(tx, `reminder:${intent.userId}`);
			const existing = await tx.deliveryAttempt.findUnique({
				where: { intentId },
			});
			if (existing && (existing.state !== "retryable" || existing.startedAt))
				return null;
			const eligible = await this.eligibility(tx, intentId, now);
			if ("reason" in eligible) {
				if (eligible.reason !== "not_due")
					await tx.reminderIntent.update({
						where: { id: intentId },
						data: { state: "cancelled", reason: eligible.reason },
					});
				return null;
			}
			if (existing) {
				await tx.reminderIntent.update({
					where: { id: intentId },
					data: { state: "reserved", reason: null },
				});
				return tx.deliveryAttempt.update({
					where: { id: existing.id },
					data: {
						state: "reserved",
						reason: null,
						phoneNumber: eligible.user.phoneNumber,
					},
				});
			}
			const recent = await tx.deliveryAttempt.findMany({
				where: {
					channel: "voice",
					userId: intent.userId,
					createdAt: { gte: new Date(now.getTime() - 48 * 60 * 60_000) },
				},
			});
			const daily = recent.filter(
				(a) =>
					localDay(a.createdAt, eligible.preference.timeZone) ===
					localDay(now, eligible.preference.timeZone),
			).length;
			const hourly = await tx.deliveryAttempt.count({
				where: {
					channel: "voice",
					createdAt: { gte: new Date(now.getTime() - 60 * 60_000) },
				},
			});
			if (
				daily >= Math.min(eligible.preference.maxCallsPerDay, 2) ||
				hourly >= this.config.maxCallsPerHour
			) {
				await tx.reminderIntent.update({
					where: { id: intentId },
					data: { state: "cancelled", reason: "call_limit" },
				});
				return null;
			}
			await tx.reminderIntent.update({
				where: { id: intentId },
				data: { state: "reserved" },
			});
			return tx.deliveryAttempt.create({
				data: {
					intentId,
					userId: intent.userId,
					channel: "voice",
					phoneNumber: eligible.user.phoneNumber,
					createdAt: now,
				},
			});
		});
		if (!attempt) return { state: "suppressed" };
		const ready = await serial(this.db, async (tx) => {
			await lock(tx, "voice-budget");
			await lock(tx, `reminder:${attempt.userId}`);
			const fresh = await tx.deliveryAttempt.findUnique({
				where: { id: attempt.id },
			});
			const eligible = await this.eligibility(tx, intentId, new Date());
			if (
				fresh?.state !== "reserved" ||
				"reason" in eligible ||
				eligible.user.phoneNumber !== attempt.phoneNumber
			) {
				await tx.deliveryAttempt.update({
					where: { id: attempt.id },
					data: { state: "cancelled", reason: "dispatch_recheck" },
				});
				return false;
			}
			await tx.deliveryAttempt.update({
				where: { id: attempt.id },
				data: { state: "dispatching", startedAt: new Date() },
			});
			return true;
		});
		if (!ready) return { state: "cancelled" };
		try {
			const sent = await this.voice.send(attempt.id, attempt.phoneNumber!);
			await serial(this.db, async (tx) => {
				const fresh = await tx.deliveryAttempt.findUnique({
					where: { id: attempt.id },
				});
				if (fresh?.providerId && fresh.providerId !== sent.providerId)
					throw new Error("provider_correlation_conflict");
				await tx.deliveryAttempt.update({
					where: { id: attempt.id },
					data: {
						providerId: sent.providerId,
						...(fresh?.state === "dispatching" ? { state: "submitted" } : {}),
					},
				});
				await tx.reminderIntent.updateMany({
					where: { id: intentId, state: "reserved" },
					data: { state: "dispatched" },
				});
			});
			const stillPermitted = await serial(this.db, (tx) =>
				this.eligibility(tx, intentId, new Date()),
			);
			if ("reason" in stillPermitted) {
				try {
					await this.voice.cancel(sent.providerId);
				} catch {
					/* periodic cancellation sweep retries */
				}
			}
			return { state: "submitted", attemptId: attempt.id };
		} catch {
			// A timeout may mean Twilio accepted the call. Never blindly retry it.
			await this.db.deliveryAttempt.updateMany({
				where: { id: attempt.id, state: "dispatching" },
				data: { state: "uncertain", reason: "provider_result_unknown" },
			});
			this.emit({ event: "voice_dispatch_uncertain", count: 1 });
			return { state: "uncertain", attemptId: attempt.id };
		}
	}

	async webhook(
		attemptId: string,
		body: Record<string, string>,
		kind: "status" | "voice" | "input",
	) {
		return serial(this.db, async (tx) => {
			const attempt = await tx.deliveryAttempt.findUnique({
				where: { id: attemptId },
			});
			if (
				!attempt ||
				!attempt.startedAt ||
				attempt.phoneNumber !== body.To ||
				!/^CA[0-9a-f]{32}$/i.test(body.CallSid || "") ||
				(attempt.providerId && attempt.providerId !== body.CallSid)
			)
				throw new ConsumerError(404, "Call not found.");
			await lock(tx, `reminder:${attempt.userId}`);
			if (!attempt.providerId)
				await tx.deliveryAttempt.update({
					where: { id: attemptId },
					data: { providerId: body.CallSid },
				});
			await tx.reminderIntent.updateMany({
				where: { id: attempt.intentId, state: "reserved" },
				data: { state: "dispatched" },
			});
			if (
				kind === "status" &&
				acceptProviderEvent(
					attempt.providerStatus,
					attempt.providerSequence,
					body.CallStatus,
					Number(body.SequenceNumber),
				)
			) {
				await tx.deliveryAttempt.update({
					where: { id: attemptId },
					data: {
						providerStatus: body.CallStatus,
						providerSequence: Number(body.SequenceNumber),
						state: "provider_reported",
					},
				});
			}
			// Replay-safe opt-out is available without identity checks; no voice command
			// reveals a prescription, snoozes, or changes the clinical record.
			if (kind === "input" && body.Digits === "9")
				await withdrawCalls(tx, attempt.userId, new Date());
			const result = await this.eligibility(tx, attempt.intentId, new Date());
			return {
				permitted: !("reason" in result),
				optedOut: kind === "input" && body.Digits === "9",
			};
		});
	}

	async tick(now = new Date()) {
		const startedAt = Date.now();
		const doses = await this.db.dose.findMany({
			where: {
				status: "unconfirmed",
				takenAt: null,
				snoozedUntil: null,
				canceledAt: null,
				prescription: { archivedAt: null },
				scheduledFor: {
					gte: new Date(now.getTime() - 60 * 60_000),
					lte: new Date(now.getTime() + 12 * 60 * 60_000),
				},
				OR: [
					{
						reminderIntents: {
							none: { channel: "live_activity", stage: "before" },
						},
					},
					{
						reminderIntents: {
							none: { channel: "live_activity", stage: "due" },
						},
					},
					{
						reminderIntents: {
							none: { channel: "voice", stage: "follow_up" },
						},
					},
				],
			} as Prisma.DoseWhereInput,
			select: { id: true, userId: true, scheduledFor: true },
			take: WORKER_LIMITS.planOccurrences,
			orderBy: [{ scheduledFor: "asc" }, { id: "asc" }],
		});
		const createdIntents = await this.ensurePlans(doses);
		const expired = await this.db.reminderIntent.updateMany({
			where: { state: "pending", expiresAt: { lte: now } },
			data: { state: "expired", reason: "window_expired" },
		});
		const recovered = await serial(this.db, async (tx) => {
			await lock(tx, "voice-budget");
			const stale = await tx.deliveryAttempt.findMany({
				where: {
					state: { in: ["reserved", "dispatching"] },
					updatedAt: { lt: new Date(now.getTime() - 2 * 60_000) },
				},
				select: { id: true, intentId: true, state: true, startedAt: true },
				take: WORKER_LIMITS.staleAttempts,
				orderBy: { updatedAt: "asc" },
			});
			const retryable = stale.filter(
				(attempt) => attempt.state === "reserved" && !attempt.startedAt,
			);
			const uncertain = stale.filter((attempt) => !retryable.includes(attempt));
			if (retryable.length) {
				await tx.deliveryAttempt.updateMany({
					where: {
						id: { in: retryable.map((attempt) => attempt.id) },
						state: "reserved",
						startedAt: null,
					},
					data: {
						state: "retryable",
						reason: "worker_interrupted_before_dispatch",
					},
				});
				await tx.reminderIntent.updateMany({
					where: {
						id: { in: retryable.map((attempt) => attempt.intentId) },
						state: "reserved",
					},
					data: { state: "pending", reason: null },
				});
			}
			if (uncertain.length) {
				await tx.deliveryAttempt.updateMany({
					where: {
						id: { in: uncertain.map((attempt) => attempt.id) },
						state: { in: ["reserved", "dispatching"] },
					},
					data: { state: "uncertain", reason: "worker_interrupted" },
				});
				await tx.reminderIntent.updateMany({
					where: {
						id: { in: uncertain.map((attempt) => attempt.intentId) },
						state: "reserved",
					},
					data: { state: "dispatched" },
				});
			}
			return { retryable: retryable.length, uncertain: uncertain.length };
		});
		const due = await this.db.reminderIntent.findMany({
			where: {
				channel: "voice",
				state: "pending",
				dueAt: { lte: now },
				expiresAt: { gt: now },
			},
			take: WORKER_LIMITS.dueCalls,
			orderBy: { dueAt: "asc" },
		});
		let submittedCalls = 0,
			suppressedCalls = 0;
		await mapWithConcurrency(
			due,
			WORKER_LIMITS.providerConcurrency,
			async (intent) => {
				const result = await this.dispatch(intent.id, now);
				if (result.state === "submitted") submittedCalls++;
				else suppressedCalls++;
			},
		);
		let cancelRequests = 0,
			cancelRetries = 0,
			cancelUncertain = 0;
		if (this.voice.enabled) {
			const active = await this.db.deliveryAttempt.findMany({
				where: {
					channel: "voice",
					providerId: { not: null },
					state: {
						notIn: ["cancel_requested", "cancel_uncertain", "cancelled"],
					},
					createdAt: { gte: new Date(now.getTime() - 60 * 60_000) },
					AND: [
						{
							OR: [
								{ reason: null },
								{
									reason: {
										notIn: [CANCEL_REQUESTED, CANCEL_RESULT_UNKNOWN],
									},
								},
							],
						},
						{
							OR: [
								{ providerStatus: null },
								{
									providerStatus: {
										notIn: [
											"completed",
											"busy",
											"failed",
											"no-answer",
											"canceled",
										],
									},
								},
							],
						},
					],
				},
				take: WORKER_LIMITS.activeCalls,
				orderBy: [{ updatedAt: "asc" }, { id: "asc" }],
			});
			await mapWithConcurrency(
				active,
				WORKER_LIMITS.providerConcurrency,
				async (attempt) => {
					const eligible = await serial(this.db, (tx) =>
						this.eligibility(tx, attempt.intentId, now),
					);
					if ("reason" in eligible) {
						try {
							await this.voice.cancel(attempt.providerId!);
							await this.db.deliveryAttempt.update({
								where: { id: attempt.id },
								data: {
									state: "cancel_requested",
									reason: CANCEL_REQUESTED,
								},
							});
							cancelRequests++;
						} catch {
							const failures = cancellationAttempts(attempt.reason) + 1;
							const exhausted = failures >= MAX_CANCEL_ATTEMPTS;
							await this.db.deliveryAttempt.updateMany({
								where: {
									id: attempt.id,
									state: attempt.state,
									updatedAt: attempt.updatedAt,
								},
								data: exhausted
									? {
											state: "cancel_uncertain",
											reason: CANCEL_RESULT_UNKNOWN,
										}
									: {
											state: "cancel_retry",
											reason: `cancel_retry_${failures}`,
										},
							});
							if (exhausted) cancelUncertain++;
							else cancelRetries++;
						}
					} else
						await this.db.deliveryAttempt.updateMany({
							where: {
								id: attempt.id,
								state: attempt.state,
								updatedAt: attempt.updatedAt,
							},
							// Touch checked rows so a bounded sweep fairly reaches later calls.
							data: { updatedAt: now },
						});
				},
			);
		}
		const event: ReminderEvent = {
			event: "reminder_tick",
			plannedOccurrences: doses.length,
			createdIntents,
			expiredIntents: expired.count,
			recoveredReservations: recovered.retryable,
			uncertainDispatches: recovered.uncertain,
			dueCalls: due.length,
			submittedCalls,
			suppressedCalls,
			cancelRequests,
			cancelRetries,
			cancelUncertain,
			durationMs: Date.now() - startedAt,
		};
		if (
			event.plannedOccurrences ||
			event.expiredIntents ||
			event.recoveredReservations ||
			event.uncertainDispatches ||
			event.dueCalls ||
			event.cancelRequests ||
			event.cancelRetries ||
			event.cancelUncertain
		)
			this.emit(event);
		return event;
	}
}

export function startReminderWorker(
	service: { tick(): Promise<unknown> },
	enabled = process.env.FARDA_REMINDER_WORKER_ENABLED === "true",
) {
	if (!enabled) return async () => {};
	let currentTick: Promise<void> | null = null;
	const timer = setInterval(() => {
		if (currentTick) return;
		currentTick = service
			.tick()
			.then(() => undefined)
			.catch(() => {
				console.error(JSON.stringify({ event: "reminder_worker_failed" }));
			})
			.finally(() => {
				currentTick = null;
			});
	}, 15_000);
	timer.unref();
	return async () => {
		clearInterval(timer);
		await currentTick;
	};
}
