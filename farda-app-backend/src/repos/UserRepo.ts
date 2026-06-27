import { prisma } from "@src/lib/prisma";
import type { IUser } from "@src/models/User.model";

/**
 * Get all users.
 */
async function getAll(): Promise<IUser[]> {
	return prisma.user.findMany({
		select: {
			id: true,
			phoneNumber: true,
			phoneNumberVerified: true,
			created: true,
		},
	});
}

/**
 * Add one user.
 */
async function add(user: IUser): Promise<void> {
	await prisma.user.create({
		data: user,
	});
}

/**
 * Update one user.
 */
async function update(user: IUser): Promise<void> {
	await prisma.user.update({
		where: { id: user.id },
		data: user,
	});
}

/**
 * Delete a user by their id.
 */
async function deleteOne(id: number): Promise<void> {
	await prisma.user.delete({
		where: { id },
	});
}

/**
 * Check if a user exists by their id.
 */
async function persists(id: number): Promise<boolean> {
	const user = await prisma.user.findUnique({
		where: { id },
	});
	return user !== null;
}

/******************************************************************************
                                Export default
******************************************************************************/

export default {
	getAll,
	add,
	update,
	delete: deleteOne,
	persists,
} as const;
