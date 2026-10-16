import { ConsumerError } from "../reminders/policy";

export type PharmacyPurpose = "refill" | "renewal" | "transfer" | "new_rx";
export type PharmacyAction = { mode: "external_site"; url: string };
export type PharmacyDirectoryEntry = {
	id: string;
	name: string;
	aliases: readonly string[];
	actions: Partial<Record<"refill" | "transfer", PharmacyAction>>;
	phonePolicy: "saved_prescription_only";
};

// Curated major US pharmacy options, not an exhaustive or ranked directory. Links
// are immutable official HTTPS entry points; patient/Rx data is never put in them.
export const PHARMACY_DIRECTORY: readonly PharmacyDirectoryEntry[] = [
	{
		id: "cvs",
		name: "CVS Pharmacy",
		aliases: ["cvs", "cvs pharmacy"],
		actions: {
			refill: {
				mode: "external_site",
				url: "https://www.cvs.com/content/refill",
			},
			transfer: {
				mode: "external_site",
				url: "https://www.cvs.com/content/transfer",
			},
		},
		phonePolicy: "saved_prescription_only",
	},
	{
		id: "walgreens",
		name: "Walgreens",
		aliases: ["walgreens", "walgreen"],
		actions: {
			refill: {
				mode: "external_site",
				url: "https://www.walgreens.com/topic/pharmacy.jsp",
			},
			transfer: {
				mode: "external_site",
				url: "https://www.walgreens.com/rx-checkout/guest-transfer-rx",
			},
		},
		phonePolicy: "saved_prescription_only",
	},
	{
		id: "walmart",
		name: "Walmart Pharmacy",
		aliases: ["walmart", "wal-mart", "walmart pharmacy"],
		actions: {
			refill: {
				mode: "external_site",
				url: "https://www.walmart.com/cp/pharmacy/5431",
			},
			transfer: {
				mode: "external_site",
				url: "https://www.walmart.com/cp/pharmacy/5431",
			},
		},
		phonePolicy: "saved_prescription_only",
	},
	{
		id: "costco",
		name: "Costco Pharmacy",
		aliases: ["costco", "costco pharmacy"],
		actions: {
			refill: {
				mode: "external_site",
				url: "https://rx.costco.com/prescriptions/guestrefill",
			},
			transfer: {
				mode: "external_site",
				url: "https://www.costco.com/pharmacy/warehouse-pickup",
			},
		},
		phonePolicy: "saved_prescription_only",
	},
	{
		id: "kroger",
		name: "Kroger Pharmacy",
		aliases: ["kroger", "kroger pharmacy"],
		actions: {
			refill: {
				mode: "external_site",
				url: "https://www.kroger.com/health/pharmacy",
			},
			transfer: {
				mode: "external_site",
				url: "https://www.kroger.com/health/pharmacy",
			},
		},
		phonePolicy: "saved_prescription_only",
	},
	{
		id: "amazon",
		name: "Amazon Pharmacy",
		aliases: ["amazon", "amazon pharmacy"],
		actions: {
			refill: { mode: "external_site", url: "https://pharmacy.amazon.com/" },
			transfer: {
				mode: "external_site",
				url: "https://pharmacy.amazon.com/how-it-works",
			},
		},
		phonePolicy: "saved_prescription_only",
	},
	{
		id: "publix",
		name: "Publix Pharmacy",
		aliases: ["publix", "publix pharmacy"],
		actions: {
			refill: { mode: "external_site", url: "https://www.publix.com/pharmacy" },
			transfer: {
				mode: "external_site",
				url: "https://www.publix.com/pharmacy",
			},
		},
		phonePolicy: "saved_prescription_only",
	},
	{
		id: "albertsons",
		name: "Albertsons Pharmacy",
		aliases: ["albertsons", "albertsons pharmacy"],
		actions: {
			refill: {
				mode: "external_site",
				url: "https://www.albertsons.com/pharmacy/prescriptions.html",
			},
			transfer: {
				mode: "external_site",
				url: "https://www.albertsons.com/pharmacy/prescriptions.html",
			},
		},
		phonePolicy: "saved_prescription_only",
	},
	{
		id: "safeway",
		name: "Safeway Pharmacy",
		aliases: ["safeway", "safeway pharmacy"],
		actions: {
			refill: {
				mode: "external_site",
				url: "https://www.safeway.com/pharmacy/prescriptions.html",
			},
			transfer: {
				mode: "external_site",
				url: "https://www.safeway.com/pharmacy/prescriptions.html",
			},
		},
		phonePolicy: "saved_prescription_only",
	},
	{
		id: "heb",
		name: "H-E-B Pharmacy",
		aliases: ["h-e-b", "heb", "h e b", "h-e-b pharmacy"],
		actions: {
			refill: { mode: "external_site", url: "https://www.heb.com/pharmacy" },
			transfer: { mode: "external_site", url: "https://www.heb.com/pharmacy" },
		},
		phonePolicy: "saved_prescription_only",
	},
	{
		id: "sams-club",
		name: "Sam's Club Pharmacy",
		aliases: ["sam's club", "sams club", "sam's club pharmacy"],
		actions: {
			refill: {
				mode: "external_site",
				url: "https://www.samsclub.com/health-and-wellness/cp/pharmacy/16670402",
			},
			transfer: {
				mode: "external_site",
				url: "https://www.samsclub.com/health-and-wellness/cp/pharmacy/16670402",
			},
		},
		phonePolicy: "saved_prescription_only",
	},
	{
		id: "meijer",
		name: "Meijer Pharmacy",
		aliases: ["meijer", "meijer pharmacy"],
		actions: {
			refill: {
				mode: "external_site",
				url: "https://www.meijer.com/services/pharmacy.html",
			},
			transfer: {
				mode: "external_site",
				url: "https://www.meijer.com/services/pharmacy.html",
			},
		},
		phonePolicy: "saved_prescription_only",
	},
] as const;

const normalize = (value: string) =>
	value
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, " ")
		.trim();
function matchesExactPharmacyName(
	entry: PharmacyDirectoryEntry,
	value: string,
): boolean {
	const normalized = normalize(value);
	return [entry.name, ...entry.aliases].some(
		(candidate) => normalize(candidate) === normalized,
	);
}
export function listPharmacies(query?: string) {
	const needle = query ? normalize(query) : "";
	return PHARMACY_DIRECTORY.filter(
		(entry) =>
			!needle ||
			[entry.name, ...entry.aliases].some(
				(value) =>
					normalize(value).includes(needle) ||
					needle.includes(normalize(value)),
			),
	);
}

type PrescriptionRecord = {
	id: string;
	userId: string;
	pharmacyOrDoctorName?: string | null;
	contactDetails?: string | null;
	labelReviewedAt?: Date | null;
	rxNumber?: string | null;
};
type PharmacyDb = {
	prescription: {
		findFirst(args: unknown): Promise<PrescriptionRecord | null>;
	};
};
const exactUsPhone = /^\+1[2-9]\d{9}$/;

export class PharmacyHandoffService {
	constructor(private readonly db: PharmacyDb) {}
	directory(query?: string) {
		return {
			data: listPharmacies(query),
			meta: {
				scope: "curated_major_us_chains" as const,
				verifiedOn: "2026-10-16",
			},
		};
	}
	async handoff(
		userId: string,
		prescriptionId: string,
		pharmacyId: string,
		purpose: PharmacyPurpose,
	) {
		const prescription = await this.db.prescription.findFirst({
			where: { id: prescriptionId, userId, archivedAt: null },
		});
		if (!prescription) throw new ConsumerError(404, "Prescription not found");
		const pharmacy = PHARMACY_DIRECTORY.find((item) => item.id === pharmacyId);
		if (!pharmacy) throw new ConsumerError(404, "Pharmacy option not found");
		const action =
			purpose === "renewal" || purpose === "new_rx"
				? { mode: "call_prescriber" as const }
				: pharmacy.actions[purpose];
		if (!action)
			throw new ConsumerError(
				409,
				"This handoff is not available for the selected pharmacy",
			);
		const savedNameMatches =
			!!prescription.pharmacyOrDoctorName &&
			matchesExactPharmacyName(pharmacy, prescription.pharmacyOrDoctorName);
		const savedPharmacyPhone =
			prescription.labelReviewedAt &&
			savedNameMatches &&
			prescription.contactDetails &&
			exactUsPhone.test(prescription.contactDetails)
				? prescription.contactDetails
				: undefined;
		return {
			data: {
				pharmacy: { id: pharmacy.id, name: pharmacy.name },
				purpose,
				action,
				...(savedPharmacyPhone ? { savedPharmacyPhone } : {}),
				copyFields:
					purpose === "refill" || purpose === "transfer" ? ["rxNumber"] : [],
				notice:
					purpose === "renewal" || purpose === "new_rx"
						? "A licensed prescriber must send or renew the prescription. Farda has not contacted them."
						: "Continue on the pharmacy's official site and review the request there. Farda has not sent or submitted a prescription request.",
			},
		};
	}
}
