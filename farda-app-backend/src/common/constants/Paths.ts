const Paths = {
	_: "/api",
	// Auth (#7/#8/#9) is owned by better-auth, mounted via `toNodeHandler(auth)`
	// on `/api/auth/*` in server.ts. There are no hand-rolled auth route paths
	// here anymore — better-auth's plugins expose the phone/OTP + session
	// endpoints under this prefix directly.
	//
	// NOTE: the `Users` (#35 numeric-id scaffold), `DeviceUser` and `Caregiver`
	// (#14/#30 dead FARDA_API_URL proxy) path groups were removed alongside their
	// routers.
	Auth: {
		_: "/auth",
	},
	Prescription: {
		_: "/prescriptions",
		Create: "/prescriptions",
		GetAll: "/prescriptions",
		SetupVial: "/prescriptions/:prescriptionId/vial",
		RemoveVial: "/prescriptions/:prescriptionId/vial/:deviceId",
		Delete: "/prescriptions/:prescriptionId",
		OcrExtract: "/prescriptions/ocr/extract",
		OcrExtractFromUrls: "/prescriptions/ocr/extract-from-urls",
		OcrSave: "/prescriptions/ocr/save",
		OcrGetUser: "/prescriptions/ocr/user/:userId",
		OcrGetUserDoses: "/prescriptions/ocr/user/:userId/doses",
		OcrRecordDose: "/prescriptions/ocr/doses/:doseId/record",
	},
	// Reminder + notification engine (GTM-537). All routes session-gated (A2).
	Reminders: {
		_: "/reminders",
		// GET the authenticated user's upcoming reminder schedule (derived from
		// their Dose rows + per-prescription reminder config + delivery prefs).
		Schedule: "/reminders/schedule",
		// POST a single reminder-response event (delivered/opened/snoozed/...).
		Events: "/reminders/events",
		// PUT the user's delivery preferences (timezone + quiet hours).
		Preferences: "/reminders/preferences",
		// POST register an FCM/APNs push token for this device (SCAFFOLD).
		PushTokens: "/reminders/push-tokens",
	},
	// Refill prediction + pharmacy-readiness (GTM-541). All routes session-gated.
	Refills: {
		_: "/refills",
		// GET per-prescription remaining / days-left / refill-due (derived on read
		// from Prescription qty + Dose rows).
		GetAll: "/refills",
		// POST a single refill lifecycle event (requested/completed/delayed).
		Events: "/refills/events",
		// GET refill-adherence metrics for the session user.
		Metrics: "/refills/metrics",
	},
	// Enterprise analytics export (GTM-522). ADMIN-ONLY + session-gated. Serves
	// ONLY the de-identified / analytic layers — NEVER raw PHI.
	Analytics: {
		_: "/analytics",
		// GET the analytic-layer metric roll-ups (PHI-free, k-anonymity-guarded).
		Metrics: "/analytics/metrics",
		// GET an integrity report for the provenance ledger (hash-chain verify).
		ProvenanceVerify: "/analytics/provenance/verify",
	},
	// Adherence-metrics computation engine (GTM-540 / GTM-502). Session-gated;
	// derived on read from the user's Dose rows + Rx/Medicine inventory.
	Metrics: {
		_: "/metrics",
		// GET the 9 adherence metrics for the authenticated user over a date range
		// (optional ?start=&end=&prescriptionId=). IDOR-guarded to req.user.id.
		Adherence: "/metrics/adherence",
	},
	// In-product tiered consent capture (GTM-523). Session-gated + IDOR-guarded to
	// req.user.id. The source-of-truth the provenance ledger + data pipeline read
	// to stamp + gate every record. All changes audited + written to provenance.
	Consent: {
		_: "/consent",
		// POST record / update the session user's consent (append-only history).
		Record: "/consent",
		// GET the session user's CURRENT (latest non-revoked) consent.
		Current: "/consent",
		// GET the session user's full append-only consent history.
		History: "/consent/history",
	},
};

export default Paths;
