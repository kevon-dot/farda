import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "../generated/prisma/client";
import {
	DEFAULT_PREFERENCE,
	VOICE_CONSENT_VERSION,
} from "../src/reminders/policy";
import { ReminderService } from "../src/reminders/service";
import { RefillService } from "../src/refills/service";

// The runner must supply a disposable DB with BOTH consumer-core and reminder
// migrations applied. No default DATABASE_URL fallback: never touch production.
const databaseUrl = process.env.TEST_DATABASE_URL;
const singleConnectionEngine =
	process.env.TEST_DATABASE_SINGLE_CONNECTION === "true";
describe.skipIf(!databaseUrl)(
	"reminders/refills PostgreSQL integration",
	() => {
		let db: PrismaClient;
		const prefix = `reminder-it-${Date.now()}-${Math.random().toString(16).slice(2)}`;
		const userId = `${prefix}-user`,
			otherId = `${prefix}-other`,
			prescriptionId = `${prefix}-rx`;
		const config = {
			enabled: true,
			accountSid: "AC" + "1".repeat(32),
			authToken: "test",
			from: "+15555550000",
			publicOrigin: "https://farda.example",
			allowedPrefixes: ["+1"],
			maxCallsPerHour: 100,
		};
		let counter = 0;
		const adapter = {
			enabled: true,
			send: vi.fn(async () => ({
				providerId: "CA" + String(++counter).padStart(32, "0"),
			})),
			cancel: vi.fn(async () => {}),
		};
		let reminders: ReminderService, refills: RefillService;
		beforeAll(async () => {
			db = new PrismaClient({
				adapter: new PrismaPg({
					connectionString: databaseUrl!,
					max: process.env.TEST_DATABASE_SINGLE_CONNECTION === "true" ? 1 : 4,
				}),
			});
			reminders = new ReminderService(db, adapter, config);
			refills = new RefillService(db);
			await db.user.createMany({
				data: [
					{
						id: userId,
						phoneNumber: `+1555${String(Date.now()).slice(-7)}`,
						phoneNumberVerified: true,
					},
					{ id: otherId },
				],
			});
			await db.prescription.create({
				data: {
					id: prescriptionId,
					userId,
					medicationName: "Integration fixture only",
				},
			});
			const user = await db.user.findUniqueOrThrow({ where: { id: userId } });
			// Choose quiet hours guaranteed outside now in UTC, preserving a real timezone.
			const hour = new Date().getUTCHours(),
				start = `${String((hour + 2) % 24).padStart(2, "0")}:00`,
				end = `${String((hour + 3) % 24).padStart(2, "0")}:00`;
			await db.reminderPreference.create({
				data: {
					userId,
					...DEFAULT_PREFERENCE,
					callsEnabled: true,
					timeZone: "UTC",
					quietHoursStart: start,
					quietHoursEnd: end,
				},
			});
			await db.channelConsent.create({
				data: {
					userId,
					phoneNumber: user.phoneNumber!,
					wordingVersion: VOICE_CONSENT_VERSION,
				},
			});
		}, 30000);
		afterAll(async () => {
			if (db) {
				await db.user.deleteMany({ where: { id: { in: [userId, otherId] } } });
				await db.$disconnect();
			}
		});
		async function newDose(suffix: string) {
			const dose = await db.dose.create({
				data: {
					id: `${prefix}-${suffix}`,
					prescriptionId,
					userId,
					scheduledFor: new Date(Date.now() - 10 * 60_000),
				},
			});
			await reminders.plan(userId, dose.id);
			const intent = await db.reminderIntent.findUniqueOrThrow({
				where: {
					doseId_channel_stage: {
						doseId: dose.id,
						channel: "voice",
						stage: "follow_up",
					},
				},
			});
			return { dose, intent };
		}
		it.skipIf(singleConnectionEngine)(
			"concurrent workers reserve exactly one persistent delivery attempt on native PostgreSQL",
			async () => {
				const { intent } = await newDose("concurrent");
				const before = adapter.send.mock.calls.length;
				await Promise.all([
					reminders.dispatch(intent.id),
					reminders.dispatch(intent.id),
				]);
				expect(adapter.send.mock.calls.length - before).toBe(1);
				expect(
					await db.deliveryAttempt.count({ where: { intentId: intent.id } }),
				).toBe(1);
			},
		);
		it("replayed workers reserve exactly one persistent delivery attempt", async () => {
			const { intent } = await newDose("replayed");
			const before = adapter.send.mock.calls.length;
			await reminders.dispatch(intent.id);
			await reminders.dispatch(intent.id);
			expect(adapter.send.mock.calls.length - before).toBe(1);
			expect(
				await db.deliveryAttempt.count({ where: { intentId: intent.id } }),
			).toBe(1);
		});
		it("does not dispatch after a canonical status update", async () => {
			const { dose, intent } = await newDose("resolved");
			// SQL references the canonical core field even when generated in an isolated
			// additive worktree. Final generated client includes it normally.
			await db.$executeRaw`UPDATE "Dose" SET "status" = 'taken', "takenAt" = now() WHERE "id" = ${dose.id}`;
			const before = adapter.send.mock.calls.length;
			await reminders.dispatch(intent.id);
			expect(adapter.send.mock.calls.length).toBe(before);
			expect(
				(
					await db.reminderIntent.findUniqueOrThrow({
						where: { id: intent.id },
					})
				).state,
			).toBe("cancelled");
		});
		it("persisted snooze cancels intents, increments canonical revision, and audits", async () => {
			const { dose } = await newDose("snooze");
			const result = await reminders.snooze(userId, dose.id, 15, 0);
			expect(result.revision).toBe(1);
			expect(
				(
					await db.reminderIntent.findMany({ where: { doseId: dose.id } })
				).every((i) => i.state === "cancelled"),
			).toBe(true);
			const audit = await db.$queryRaw<
				{ reason: string }[]
			>`SELECT "reason" FROM "DoseCorrection" WHERE "doseId" = ${dose.id}`;
			expect(audit[0]?.reason).toBe("user_snoozed");
		});
		it("foreign identities cannot mutate occurrence, inventory, or receipt", async () => {
			const { dose } = await newDose("ownership");
			await expect(
				reminders.snooze(otherId, dose.id, 15),
			).rejects.toMatchObject({ status: 404 });
			await expect(
				refills.inventory(otherId, prescriptionId),
			).rejects.toMatchObject({ status: 404 });
		});
		it("replayed receipts add stock exactly once with durable uniqueness", async () => {
			await refills.count(userId, prescriptionId, {
				quantity: 6,
				observedAt: new Date(Date.now() - 3600_000),
				idempotencyKey: `${prefix}-count`,
			});
			const { refill } = await refills.create(userId, {
				prescriptionId,
				kind: "refill",
			});
			await refills.status(userId, refill.id, "received");
			const body = {
				quantity: 30,
				inventoryRevision: 1,
				alreadyIncluded: false,
				idempotencyKey: `${prefix}-receipt`,
			};
			const result = [
				await refills.receipt(userId, refill.id, body),
				await refills.receipt(userId, refill.id, body),
			];
			expect(result.map((r) => r.duplicate).sort()).toEqual([false, true]);
			expect(
				(
					await db.inventoryBalance.findUniqueOrThrow({
						where: { prescriptionId },
					})
				).quantity,
			).toBe(36);
			expect(
				await db.inventoryEntry.count({ where: { refillId: refill.id } }),
			).toBe(1);
			const listed = (await refills.list(userId)).refills.find(
				(item) => item.id === refill.id,
			);
			expect(listed?.receiptReconciled).toBe(true);
			expect(listed?.receipt?.quantity).toBe(30);
			await expect(
				refills.receipt(otherId, refill.id, body),
			).rejects.toMatchObject({ status: 404 });
		});
		it.skipIf(singleConnectionEngine)(
			"concurrent receipt retries add stock once on native PostgreSQL",
			async () => {
				const { refill } = await refills.create(userId, {
					prescriptionId,
					kind: "renewal",
				});
				await refills.status(userId, refill.id, "received");
				const body = {
					quantity: 30,
					inventoryRevision: 2,
					alreadyIncluded: false,
					idempotencyKey: `${prefix}-concurrent-receipt`,
				};
				const result = await Promise.all([
					refills.receipt(userId, refill.id, body),
					refills.receipt(userId, refill.id, body),
				]);
				expect(result.map((r) => r.duplicate).sort()).toEqual([false, true]);
				expect(
					(
						await db.inventoryBalance.findUniqueOrThrow({
							where: { prescriptionId },
						})
					).quantity,
				).toBe(66);
				expect(
					await db.inventoryEntry.count({ where: { refillId: refill.id } }),
				).toBe(1);
			},
		);
		it("foreign keys prevent orphan intents and account deletion removes private consent", async () => {
			await expect(
				db.reminderIntent.create({
					data: {
						userId,
						doseId: "missing-dose",
						channel: "voice",
						stage: "follow_up",
						dueAt: new Date(),
						expiresAt: new Date(),
					},
				}),
			).rejects.toMatchObject({ code: "P2003" });
			const disposable = `${prefix}-delete`;
			await db.user.create({ data: { id: disposable } });
			await db.channelConsent.create({
				data: {
					userId: disposable,
					phoneNumber: "+15555550111",
					wordingVersion: VOICE_CONSENT_VERSION,
				},
			});
			await db.user.delete({ where: { id: disposable } });
			expect(
				await db.channelConsent.count({ where: { userId: disposable } }),
			).toBe(0);
		});
	},
);
