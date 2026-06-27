import type { z } from "zod";

/******************************************************************************
                                Types
******************************************************************************/

type ValidationError = {
	message: string;
	errors: z.ZodError["issues"];
};

/******************************************************************************
                                Functions
******************************************************************************/

/**
 * JSON parse a validation error.
 */
export function parseValidationError(arg: unknown): ValidationError {
	if (typeof arg !== "string") {
		throw new Error("Not a string");
	}
	const parsed = JSON.parse(arg);
	return parsed as ValidationError;
}
