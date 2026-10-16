import { createHash } from "node:crypto";
import type { PrismaClient } from "../../generated/prisma/client";
import { ConsumerError } from "../reminders/policy";
import { lock, serial, type Transaction } from "../reminders/service";

const hash = (input: unknown) =>
	createHash("sha256").update(JSON.stringify(input)).digest("hex");
async function ownedPrescription(
	tx: Transaction,
	userId: string,
	prescriptionId: string,
) {
	const prescription = await tx.prescription.findFirst({
		where: { id: prescriptionId, userId },
	});
	if (!prescription) throw new ConsumerError(404, "Prescription not found.");
	return prescription;
}
export function receiptDelta(quantity: number, alreadyIncluded: boolean) {
	return alreadyIncluded ? 0 : quantity;
}
export function inventoryPresentation(
	balance: {
		quantity: number;
		observedAt: Date;
		revision: number;
		source: string;
		updatedAt: Date;
	} | null,
	now = new Date(),
) {
	return {
		inventory: balance
			? {
					...balance,
					stale:
						now.getTime() - balance.observedAt.getTime() > 7 * 24 * 60 * 60_000,
					label: "Last reconciled supply",
					automaticallyDecremented: false,
				}
			: null,
		estimate: null,
		estimateReason:
			"A count and receipt ledger do not establish current consumption. No days-left estimate is calculated.",
		pharmacyConnected: false,
	};
}
export class RefillService {
	constructor(private db: PrismaClient) {}
	async list(userId: string) {
		const [refills, prescriptions, balances] = await Promise.all([
			this.db.refillIntent.findMany({
				where: { userId },
				include: {
					receipt: {
						select: { id: true, quantity: true, delta: true, createdAt: true },
					},
				},
				orderBy: { createdAt: "desc" },
				take: 100,
			}),
			this.db.prescription.findMany({
				where: { userId, archivedAt: null },
				select: { id: true },
			}),
			this.db.inventoryBalance.findMany({ where: { userId } }),
		]);
		const byPrescription = new Map(
			balances.map((balance) => [balance.prescriptionId, balance]),
		);
		return {
			inventories: prescriptions.map((prescription) => ({
				prescriptionId: prescription.id,
				...inventoryPresentation(byPrescription.get(prescription.id) ?? null),
			})),
			refills: refills.map((r) => ({
				...r,
				receiptReconciled: !!r.receipt,
				userReported: true,
				pharmacyConfirmed: false,
			})),
			pharmacyConnected: false,
		};
	}
	async create(
		userId: string,
		input: { prescriptionId: string; kind: string; plannedFor?: Date },
	) {
		return serial(this.db, async (tx) => {
			await ownedPrescription(tx, userId, input.prescriptionId);
			await lock(tx, `inventory:${input.prescriptionId}`);
			const active = await tx.refillIntent.findFirst({
				where: {
					userId,
					prescriptionId: input.prescriptionId,
					kind: input.kind,
					status: { in: ["planned", "contacted", "ready"] },
				},
			});
			if (active)
				return {
					refill: { ...active, userReported: true, pharmacyConfirmed: false },
					duplicate: true,
				};
			const refill = await tx.refillIntent.create({
				data: { userId, ...input },
			});
			await tx.refillEvent.create({
				data: { userId, refillId: refill.id, status: "planned" },
			});
			return {
				refill: { ...refill, userReported: true, pharmacyConfirmed: false },
				duplicate: false,
			};
		});
	}
	async status(userId: string, refillId: string, status: string) {
		return serial(this.db, async (tx) => {
			const refill = await tx.refillIntent.findFirst({
				where: { id: refillId, userId },
			});
			if (!refill) throw new ConsumerError(404, "Refill plan not found.");
			await ownedPrescription(tx, userId, refill.prescriptionId);
			await lock(tx, `inventory:${refill.prescriptionId}`);
			if (refill.status === status)
				return {
					refill: { ...refill, userReported: true, pharmacyConfirmed: false },
				};
			if (refill.status === "cancelled" || refill.status === "received")
				throw new ConsumerError(409, "This refill plan is closed.");
			const updated = await tx.refillIntent.update({
				where: { id: refillId },
				data: { status },
			});
			await tx.refillEvent.create({ data: { userId, refillId, status } });
			return {
				refill: { ...updated, userReported: true, pharmacyConfirmed: false },
			};
		});
	}
	async inventory(userId: string, prescriptionId: string) {
		await ownedPrescription(this.db, userId, prescriptionId);
		return inventoryPresentation(
			await this.db.inventoryBalance.findFirst({
				where: { prescriptionId, userId },
			}),
		);
	}
	async count(
		userId: string,
		prescriptionId: string,
		input: {
			quantity: number;
			observedAt: Date;
			revision?: number;
			idempotencyKey: string;
		},
	) {
		const requestHash = hash({
			kind: "count",
			prescriptionId,
			quantity: input.quantity,
			observedAt: input.observedAt.toISOString(),
		});
		return serial(this.db, async (tx) => {
			await ownedPrescription(tx, userId, prescriptionId);
			await lock(tx, `inventory:${prescriptionId}`);
			const previous = await tx.inventoryEntry.findUnique({
				where: {
					userId_requestKey: { userId, requestKey: input.idempotencyKey },
				},
			});
			if (previous) {
				if (previous.requestHash !== requestHash)
					throw new ConsumerError(
						409,
						"This request key was already used for another inventory change.",
					);
				return {
					...inventoryPresentation(
						await tx.inventoryBalance.findUnique({ where: { prescriptionId } }),
					),
					duplicate: true,
				};
			}
			const current = await tx.inventoryBalance.findUnique({
				where: { prescriptionId },
			});
			if (!current && input.revision !== undefined)
				throw new ConsumerError(
					409,
					"Supply changed. Refresh the count before saving.",
				);
			if (current && input.revision !== current.revision)
				throw new ConsumerError(
					409,
					"Supply changed. Refresh the count before saving.",
				);
			if (current && input.observedAt < current.observedAt)
				throw new ConsumerError(409, "A more recent count already exists.");
			const inventory = await tx.inventoryBalance.upsert({
				where: { prescriptionId },
				create: {
					prescriptionId,
					userId,
					quantity: input.quantity,
					observedAt: input.observedAt,
				},
				update: {
					quantity: input.quantity,
					observedAt: input.observedAt,
					source: "user_count",
					revision: { increment: 1 },
				},
			});
			await tx.inventoryEntry.create({
				data: {
					userId,
					prescriptionId,
					kind: "count",
					quantity: input.quantity,
					delta: input.quantity - (current?.quantity || 0),
					observedAt: input.observedAt,
					requestKey: input.idempotencyKey,
					requestHash,
				},
			});
			return { ...inventoryPresentation(inventory), duplicate: false };
		});
	}
	async receipt(
		userId: string,
		refillId: string,
		input: {
			quantity: number;
			inventoryRevision: number;
			alreadyIncluded: boolean;
			idempotencyKey: string;
		},
	) {
		const requestHash = hash({
			kind: "receipt",
			refillId,
			quantity: input.quantity,
			alreadyIncluded: input.alreadyIncluded,
		});
		return serial(this.db, async (tx) => {
			const refill = await tx.refillIntent.findFirst({
				where: { id: refillId, userId },
			});
			if (!refill) throw new ConsumerError(404, "Refill plan not found.");
			await ownedPrescription(tx, userId, refill.prescriptionId);
			await lock(tx, `inventory:${refill.prescriptionId}`);
			const previous = await tx.inventoryEntry.findFirst({
				where: {
					OR: [{ userId, requestKey: input.idempotencyKey }, { refillId }],
				},
			});
			if (previous) {
				if (previous.userId !== userId || previous.requestHash !== requestHash)
					throw new ConsumerError(
						409,
						"This receipt or request was already reconciled with different details.",
					);
				return {
					...inventoryPresentation(
						await tx.inventoryBalance.findUnique({
							where: { prescriptionId: refill.prescriptionId },
						}),
					),
					receipt: previous,
					duplicate: true,
				};
			}
			if (refill.status !== "received")
				throw new ConsumerError(
					409,
					"Confirm you received the refill before reconciling supply.",
				);
			const balance = await tx.inventoryBalance.findUnique({
				where: { prescriptionId: refill.prescriptionId },
			});
			if (!balance)
				throw new ConsumerError(
					409,
					"Record a count first, then confirm whether it includes this refill.",
				);
			if (balance.revision !== input.inventoryRevision)
				throw new ConsumerError(
					409,
					"Supply changed. Refresh before adding this receipt.",
				);
			if (!input.alreadyIncluded && balance.observedAt >= refill.updatedAt)
				throw new ConsumerError(
					409,
					"Your count is newer than this receipt. Reconcile whether it already includes the refill.",
				);
			const delta = receiptDelta(input.quantity, input.alreadyIncluded);
			if (balance.quantity + delta > 100000)
				throw new ConsumerError(400, "Supply quantity is too large.");
			const inventory = await tx.inventoryBalance.update({
				where: { prescriptionId: refill.prescriptionId },
				data: {
					quantity: { increment: delta },
					revision: { increment: 1 },
					source: "user_count_and_receipt",
				},
			});
			const receipt = await tx.inventoryEntry.create({
				data: {
					userId,
					prescriptionId: refill.prescriptionId,
					refillId,
					kind: "receipt",
					quantity: input.quantity,
					delta,
					observedAt: refill.updatedAt,
					requestKey: input.idempotencyKey,
					requestHash,
				},
			});
			return { ...inventoryPresentation(inventory), receipt, duplicate: false };
		});
	}
}
