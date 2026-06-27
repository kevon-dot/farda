import * as fs from "node:fs";
import env from "@src/common/constants/env";
import OpenAI from "openai";

interface Medicine {
	medicine_name: string;
	generic_name: string;
	instructions: string;
	qty: string;
	refills_info: string;
	side_effects: string;
}

export interface ExtractedPrescriptionData {
	pharmacy_or_doctor_name: string;
	contact_details: string;
	date_filled: string;
	date_expired: string;
	address: string;
	rx_number: string;
	store_number: string;
	medicines_names: Medicine[];
}

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

		// Clean markdown formatting if present
		let cleanedContent = responseText;
		if (cleanedContent.startsWith("```json")) {
			cleanedContent = cleanedContent.replace(/```json|```/g, "").trim();
		} else if (cleanedContent.startsWith("```")) {
			cleanedContent = cleanedContent.replace(/```/g, "").trim();
		}

		const parsedData = JSON.parse(cleanedContent);

		return {
			pharmacy_or_doctor_name: parsedData.pharmacy_or_doctor_name || "none",
			contact_details: parsedData.contact_details || "none",
			date_filled: parsedData.date_filled || "none",
			date_expired: parsedData.date_expired || "none",
			address: parsedData.address || "none",
			rx_number: parsedData.rx_number || "none",
			store_number: parsedData.store_number || "none",
			medicines_names: parsedData.medicines_names || [],
		};
	} catch (error: any) {
		console.error("OCR Extraction Error:", error);

		if (error instanceof SyntaxError) {
			return {
				error: `Failed to parse OCR response: ${error.message}`,
			};
		}

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

		// Clean markdown formatting if present
		let cleanedContent = responseText;
		if (cleanedContent.startsWith("```json")) {
			cleanedContent = cleanedContent.replace(/```json|```/g, "").trim();
		} else if (cleanedContent.startsWith("```")) {
			cleanedContent = cleanedContent.replace(/```/g, "").trim();
		}

		const parsedData = JSON.parse(cleanedContent);

		return {
			pharmacy_or_doctor_name: parsedData.pharmacy_or_doctor_name || "none",
			contact_details: parsedData.contact_details || "none",
			date_filled: parsedData.date_filled || "none",
			date_expired: parsedData.date_expired || "none",
			address: parsedData.address || "none",
			rx_number: parsedData.rx_number || "none",
			store_number: parsedData.store_number || "none",
			medicines_names: parsedData.medicines_names || [],
		};
	} catch (error: any) {
		console.error("OCR Extraction Error:", error);

		if (error instanceof SyntaxError) {
			return {
				error: `Failed to parse OCR response: ${error.message}`,
			};
		}

		return {
			error: `OCR processing failed: ${error.message || "Unknown error"}`,
		};
	}
}
