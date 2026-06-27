import { ValidationError } from "@src/common/utils/route-errors";
import { z } from "zod";

/******************************************************************************
                              Functions
******************************************************************************/

/**
 * Throw a "ValidationError" when Zod schema validation fails.
 */
function parseReq<T>(schema: z.ZodSchema<T>) {
	return (data: unknown) => {
		try {
			return schema.parse(data);
		} catch (error) {
			if (error instanceof z.ZodError) {
				throw new ValidationError(error);
			}
			throw error;
		}
	};
}

export default parseReq;
