import { z } from "zod";

import type { Entity } from "./common/types";

/******************************************************************************
                                 Constants
******************************************************************************/

const GetDefaults = (): IUser => ({
	id: 0,
	phoneNumber: null,
	phoneNumberVerified: false,
	created: new Date(),
});

export const userSchema = z.object({
	id: z.number().int().nonnegative(),
	phoneNumber: z.string(),
	email: z.email(),
	created: z.date(),
});

export const userCompleteSchema = z.object({
	id: z.number().int().nonnegative(),
	name: z.string().min(1),
	email: z.string().email().min(1),
	created: z.date(),
	phoneNumber: z.string().nullable().optional().default(null),
	phoneNumberVerified: z.boolean().optional().default(false),
});

/******************************************************************************
                                  Types
******************************************************************************/

/**
 * @entity users
 */
export interface IUser extends Entity {
	id: number;
	phoneNumber: string | null;
	phoneNumberVerified?: boolean;
}

/******************************************************************************
                                  Setup
******************************************************************************/

// Set the "parseUser" function
const parseUser = (data: unknown, _: (errors: any) => never) => {
	const parsed = userSchema.parse(data);
	return parsed as IUser;
};

// For the APIs make sure the right fields are complete
const isCompleteUser = (data: unknown) => {
	return userCompleteSchema.parse(data) as IUser;
};

/******************************************************************************
                                 Functions
******************************************************************************/

/**
 * New user object.
 */
function new_(user?: Partial<IUser>): IUser {
	return parseUser({ ...GetDefaults(), ...user }, (errors) => {
		throw new Error(`Setup new user failed ${JSON.stringify(errors, null, 2)}`);
	});
}

/******************************************************************************
                                Export default
******************************************************************************/

export default {
	new: new_,
	isComplete: isCompleteUser,
} as const;
