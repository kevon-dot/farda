import * as fs from "node:fs";
import env from "@src/common/constants/env";
import OpenAI from "openai";
import { type OcrResult, validateOcrResult } from "./ocrSchema";

// The extracted, VALIDATED prescription data is exactly the schema-derived
// type. Persisting/returning anything that hasn't passed the schema is a bug.
export type ExtractedPrescriptionData = OcrResult;

// Lazy load OpenAI to avoid initialization errors when API key is missing
let openaiInstance: OpenAI | null = null;

function getOpenAIClient(): OpenAI | null {
	if (openaiInstance === null && env.OPENAI_API_KEY) {
		try {
			openaiInstance = new OpenAI({
				apiKey: env.OPENAI_API_KEY,
			});
		} catch (err) {
			console.error("Failed to initialize OpenAI client:", err);
			return null;
		}
	}
	return env.OPENAI_API_KEY ? openaiInstance : null;
}

const MODEL = "gpt-4o";
const TEMPERATURE = 0.5;

const SYSTEM_PROMPT = {
	role: "system",
	content:
		"You are a medical assistant that extracts structured data from prescription images. Respond only with valid JSON based on the user's instructions.",
};

/**
 * Log offending model output server-side without leaking full PHI to stdout
 * in production. The raw extraction is potential PHI; in prod we log only the
 * validation error and a redacted summary, never the full payload.
 */
function logInvalidOcrOutput(error: unknown, rawSnippet: string): void {
	const isProd = env.NODE_ENV === "production";
	if (isProd) {
		// PHI-aware: do NOT emit the raw model output. Length + error only.
		console.error(
			"OCR output failed schema validation (raw output withheld in production).",
			{
				rawLength: rawSnippet.length,
				validationError: error instanceof Error ? error.message : String(error),
			},
		);
	} else {
		// In non-prod, include a bounded snippet to aid debugging.
		console.error("OCR output failed schema validation.", {
			validationError: error,
			rawSnippet: rawSnippet.slice(0, 1000),
		});
	}
}

/**
 * Strip markdown fencing, JSON.parse, then validate against the STRICT OCR
 * schema. Untrusted model output is never returned to callers unless it
 * passes validation. On failure we log (PHI-aware) and return a clear error
 * rather than silently persisting garbage (#33).
 */
function parseAndValidateOcrResponse(
	responseText: string,
): ExtractedPrescriptionData | { error: string } {
	let cleanedContent = responseText.trim();
	if (cleanedContent.startsWith("```json")) {
		cleanedContent = cleanedContent.replace(/```json|```/g, "").trim();
	} else if (cleanedContent.startsWith("```")) {
		cleanedContent = cleanedContent.replace(/```/g, "").trim();
	}

	let parsed: unknown;
	try {
		parsed = JSON.parse(cleanedContent);
	} catch (err) {
		logInvalidOcrOutput(err, cleanedContent);
		return {
			error:
				"OCR result was not valid JSON and was rejected. Please retry with a clearer image.",
		};
	}

	const result = validateOcrResult(parsed);
	if (!result.ok) {
		logInvalidOcrOutput(result.error, cleanedContent);
		return {
			error:
				"OCR result did not match the expected prescription schema and was rejected.",
		};
	}

	return result.data;
}

const USER_INSTRUCTION_TEXT = `
You are shown a prescription image. Extract detailed and structured medical information and return ONLY a well-formatted JSON object using the exact schema below:

{
  "pharmacy_or_doctor_name": "name of the doctor or pharmacy as seen in the image",
  "contact_details": "phone number, email, or any other contact information",
  "date_filled": "date of the prescription filled if visible",
  "date_expired": "date of the prescription expiration if visible",
  "address": "address found in the image",
  "rx_number": "prescription number found",
  "store_number": "store number found",
  "medicines_names": [
    {
      "medicine_name": "individual medicine name found",
      "generic_name": "only generic name if available, otherwise 'none'.",
      "instructions": "dosage instructions. If vague or missing, infer from context. Reconstruct clearly using medical knowledge. For example: 'Take one (1x) tablet in the morning and one (1x) at night for five (5) days.'",
      "qty": "quantity found. If not present, estimate based on dosage duration. (only number)",
      "refills_info": "refill information if available, otherwise 'none'",
      "side_effects": "any mentioned side effects."
    }
  ]
}

STRICT RULES:
- Each medicine must be a separate object in the medicines_names array.
- Use the word "none" for any field not visible or inferable from the image.
- Use clear and full-sentence structure for instructions, qty, and side_effects. Do not output vague fragments.
- Do NOT output anything except the JSON object. No commentary, no explanations.
`;

export async function extractPrescriptionFromFiles(
	imagePaths: string[],
): Promise<ExtractedPrescriptionData | { error: string }> {
	const openai = getOpenAIClient();
	if (!openai) {
		return {
			error:
				"OpenAI API key is not configured. Please set OPENAI_API_KEY environment variable.",
		};
	}

	try {
		const imageContents = imagePaths.map((filePath) => {
			const imageData = fs.readFileSync(filePath);
			const base64Image = imageData.toString("base64");

			return {
				type: "image_url" as const,
				image_url: {
					url: `data:image/jpeg;base64,${base64Image}`,
				},
			};
		});

		if (!imageContents.length) {
			return { error: "No valid image files provided" };
		}

		const userContent = [
			{ type: "text" as const, text: USER_INSTRUCTION_TEXT },
			...imageContents,
		];

		const response = await openai.chat.completions.create({
			model: MODEL,
			temperature: TEMPERATURE,
			response_format: { type: "json_object" },
			messages: [
				{
					role: "system",
					content: SYSTEM_PROMPT.content,
				},
				{
					role: "user",
					content: userContent as any,
				},
			],
			max_tokens: 2000,
		});

		const responseText = response.choices[0]?.message?.content?.trim() || "";

		return parseAndValidateOcrResponse(responseText);
	} catch (error: any) {
		console.error("OCR Extraction Error:", error);

		return {
			error: `OCR processing failed: ${error.message || "Unknown error"}`,
		};
	}
}

export async function extractPrescriptionFromUrls(
	imageUrls: string[],
): Promise<ExtractedPrescriptionData | { error: string }> {
	const openai = getOpenAIClient();
	if (!openai) {
		return {
			error:
				"OpenAI API key is not configured. Please set OPENAI_API_KEY environment variable.",
		};
	}

	try {
		const imageContents = imageUrls.map((url) => ({
			type: "image_url" as const,
			image_url: {
				url: url,
			},
		}));

		if (!imageContents.length) {
			return { error: "No valid image URLs provided" };
		}

		const userContent = [
			{ type: "text" as const, text: USER_INSTRUCTION_TEXT },
			...imageContents,
		];

		const response = await openai.chat.completions.create({
			model: MODEL,
			temperature: TEMPERATURE,
			response_format: { type: "json_object" },
			messages: [
				{
					role: "system",
					content: SYSTEM_PROMPT.content,
				},
				{
					role: "user",
					content: userContent as any,
				},
			],
			max_tokens: 2000,
		});

		const responseText = response.choices[0]?.message?.content?.trim() || "";

		return parseAndValidateOcrResponse(responseText);
	} catch (error: any) {
		console.error("OCR Extraction Error:", error);

		return {
			error: `OCR processing failed: ${error.message || "Unknown error"}`,
		};
	}
}
