import { z } from "zod";

/******************************************************************************
                                Functions
******************************************************************************/

/**
 * Convert to date object then check is a validate date.
 */
export const transformIsDate = z
	.string()
	.or(z.date())
	.transform((arg) => {
		const date = typeof arg === "string" ? new Date(arg) : arg;
		if (Number.isNaN(date.getTime())) {
			throw new Error("Invalid date");
		}
		return date;
	});
