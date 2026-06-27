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
};

export default Paths;
