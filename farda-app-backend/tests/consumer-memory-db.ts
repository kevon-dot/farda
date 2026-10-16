// Transactional in-memory test double, not a substitute for PostgreSQL tests.
// Tests use this to inject failures and recheck races without provider calls.
import type { PrismaClient } from "../generated/prisma/client";
type Row = Record<string, any>;
function match(row: Row, where: Row = {}): boolean {
	return Object.entries(where).every(([key, value]) => {
		if (key === "OR") return value.some((w: Row) => match(row, w));
		if (key === "NOT") return !match(row, value);
		if (key.includes("_") && !(key in row)) return match(row, value);
		const current = row[key];
		if (value && typeof value === "object" && !(value instanceof Date))
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
				let found = rows().filter((row) => match(row, args.where));
				if (args.orderBy) {
					const [key, dir] = Object.entries(args.orderBy)[0];
					found = [...found].sort(
						(a, b) => (a[key] < b[key] ? -1 : 1) * (dir === "asc" ? 1 : -1),
					);
				}
				return structuredClone(found.slice(0, args.take || Infinity));
			},
			async findFirst(args: Row = {}) {
				return structuredClone(
					rows().find((row) => match(row, args.where)) || null,
				);
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
				rows().push(base);
				return structuredClone(base);
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
