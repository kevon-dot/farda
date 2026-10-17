// Transactional in-memory test double, not a substitute for PostgreSQL tests.
// Tests use this to inject failures and recheck races without provider calls.
import type { PrismaClient } from "../generated/prisma/client";

type Row = Record<string, any>;
function match(row: Row, where: Row = {}): boolean {
	return Object.entries(where).every(([key, value]) => {
		if (key === "OR") return value.some((w: Row) => match(row, w));
		if (key === "AND") return value.every((w: Row) => match(row, w));
		if (key === "NOT") return !match(row, value);
		if (key.includes("_") && !(key in row)) return match(row, value);
		const current = row[key];
		if (value && typeof value === "object" && !(value instanceof Date)) {
			if (Array.isArray(current)) {
				if ("none" in value)
					return !current.some((item) => match(item, value.none));
				if ("some" in value)
					return current.some((item) => match(item, value.some));
				if ("every" in value)
					return current.every((item) => match(item, value.every));
			}
			const operators = new Set([
				"in",
				"notIn",
				"not",
				"gte",
				"lte",
				"gt",
				"lt",
			]);
			if (
				current &&
				typeof current === "object" &&
				!Object.keys(value).some((key) => operators.has(key))
			)
				return match(current, value);
			return Object.entries(value).every(([op, v]: [string, any]) =>
				op === "in"
					? v.includes(current)
					: op === "notIn"
						? !v.includes(current)
						: op === "not"
							? current !== v
							: op === "gte"
								? current >= v
								: op === "lte"
									? current <= v
									: op === "gt"
										? current > v
										: op === "lt"
											? current < v
											: false,
			);
		}
		return current instanceof Date && value instanceof Date
			? current.getTime() === value.getTime()
			: current === value;
	});
}
export function memoryDb(seed: Record<string, Row[]> = {}) {
	let tables: Record<string, Row[]> = structuredClone(seed),
		seq = 0,
		tail = Promise.resolve(),
		transactions = 0;
	const db: any = { beforeTransaction: undefined };
	const names = [
		"user",
		"prescription",
		"dose",
		"doseCorrection",
		"reminderPreference",
		"channelConsent",
		"reminderIntent",
		"deliveryAttempt",
		"liveActivityInstallation",
		"liveActivityToken",
		"liveActivityAttempt",
		"refillIntent",
		"refillEvent",
		"inventoryBalance",
		"inventoryEntry",
		"refillProviderLink",
		"refillAgentReview",
		"refillAgentRequest",
	];
	for (const name of names) {
		tables[name] ||= [];
		const rows = () => tables[name];
		const update = (row: Row, data: Row) => {
			for (const [k, v] of Object.entries(data))
				row[k] =
					v && typeof v === "object" && "increment" in v
						? (row[k] || 0) + v.increment
						: v;
			row.updatedAt = new Date();
			return structuredClone(row);
		};
		db[name] = {
			async findMany(args: Row = {}) {
				const candidates =
					name === "dose"
						? rows().map((row) => ({
								...row,
								prescription: tables.prescription.find(
									(prescription) => prescription.id === row.prescriptionId,
								),
								reminderIntents: tables.reminderIntent.filter(
									(intent) => intent.doseId === row.id,
								),
							}))
						: rows();
				let found = candidates.filter((row) => match(row, args.where));
				if (args.orderBy) {
					const clauses = Array.isArray(args.orderBy)
						? args.orderBy
						: [args.orderBy];
					found = [...found].sort((a, b) => {
						for (const clause of clauses) {
							const [key, dir] = Object.entries(clause)[0];
							if (a[key] === b[key]) continue;
							const direction = typeof dir === "object" ? dir.sort : dir;
							const nulls = typeof dir === "object" ? dir.nulls : "last";
							if (a[key] === null) return nulls === "first" ? -1 : 1;
							if (b[key] === null) return nulls === "first" ? 1 : -1;
							return (
								(a[key] < b[key] ? -1 : 1) * (direction === "asc" ? 1 : -1)
							);
						}
						return 0;
					});
				}
				const result = found.slice(0, args.take || Infinity);
				if (name === "reminderIntent" && args.select?.attempt)
					return structuredClone(
						result.map((row) => ({
							...row,
							attempt:
								tables.deliveryAttempt.find(
									(attempt) => attempt.intentId === row.id,
								) || null,
						})),
					);
				return structuredClone(result);
			},
			async findFirst(args: Row = {}) {
				return (await this.findMany({ ...args, take: 1 }))[0] || null;
			},
			async findUnique(args: Row) {
				return this.findFirst(args);
			},
			async count(args: Row = {}) {
				return rows().filter((row) => match(row, args.where)).length;
			},
			async create({ data }: Row) {
				const base = {
					id: `${name}-${++seq}`,
					createdAt: new Date(),
					updatedAt: new Date(),
					...data,
				};
				if (name === "reminderIntent")
					Object.assign(base, { state: "pending", reason: null, ...data });
				if (name === "deliveryAttempt")
					Object.assign(base, {
						state: "reserved",
						startedAt: null,
						providerId: null,
						providerStatus: null,
						providerSequence: -1,
						...data,
					});
				if (name === "liveActivityAttempt")
					Object.assign(base, {
						state: "reserved",
						startedAt: null,
						providerStatus: null,
						reason: null,
						...data,
					});
				if (name === "channelConsent")
					Object.assign(base, {
						channel: "voice",
						withdrawnAt: null,
						grantedAt: new Date(),
						...data,
					});
				if (name === "refillIntent")
					Object.assign(base, { status: "planned", ...data });
				if (name === "inventoryBalance")
					Object.assign(base, { source: "user_count", revision: 1, ...data });
				if (name === "refillAgentRequest")
					Object.assign(base, {
						providerOrderId: null,
						providerConfirmed: false,
						failureCode: null,
						lastCheckedAt: null,
						refreshClaimedAt: null,
						reconcileAttempts: 0,
						nextReconcileAt: null,
						operatorAlertedAt: null,
						...data,
					});
				rows().push(base);
				return structuredClone(base);
			},
			async createMany({ data, skipDuplicates }: Row) {
				let count = 0;
				for (const candidate of data) {
					const duplicate =
						name === "reminderIntent" &&
						rows().some(
							(row) =>
								row.doseId === candidate.doseId &&
								row.channel === candidate.channel &&
								row.stage === candidate.stage,
						);
					if (duplicate && skipDuplicates) continue;
					if (duplicate) throw new Error("unique constraint");
					await this.create({ data: candidate });
					count++;
				}
				return { count };
			},
			async update({ where, data }: Row) {
				const row = rows().find((row) => match(row, where));
				if (!row) throw new Error("missing row");
				return update(row, data);
			},
			async updateMany({ where, data }: Row) {
				const found = rows().filter((row) => match(row, where));
				for (const row of found) update(row, data);
				return { count: found.length };
			},
			async deleteMany({ where }: Row) {
				const before = tables[name].length;
				tables[name] = rows().filter((row) => !match(row, where));
				return { count: before - tables[name].length };
			},
			async upsert({ where, create, update: data }: Row) {
				const row = rows().find((row) => match(row, where));
				return row ? update(row, data) : this.create({ data: create });
			},
		};
	}
	db.$queryRaw = async () => [];
	db.$transaction = (work: (tx: any) => Promise<any>) => {
		const run = tail.then(async () => {
			transactions++;
			if (db.beforeTransaction) await db.beforeTransaction(transactions, db);
			const snapshot = structuredClone(tables);
			try {
				return await work(db);
			} catch (error) {
				tables = snapshot;
				throw error;
			}
		});
		tail = run.then(
			() => {},
			() => {},
		);
		return run;
	};
	return {
		db: db as PrismaClient,
		raw: db,
		rows: (name: string) => tables[name],
	};
}
