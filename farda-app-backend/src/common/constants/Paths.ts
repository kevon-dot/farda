const Paths = {
	_: "/api",
	Users: {
		_: "/users",
		Get: "/users/all",
		Add: "/users/add",
		Update: "/users/update",
		Delete: "/users/delete/:id",
	},
	// Auth (#7/#8/#9) is owned by better-auth, mounted via `toNodeHandler(auth)`
	// on `/api/auth/*` in server.ts. There are no hand-rolled auth route paths
	// here anymore — better-auth's plugins expose the phone/OTP + session
	// endpoints under this prefix directly.
	Auth: {
		_: "/auth",
	},
	DeviceUser: {
		_: "/user",
		Claim: "/user/claim",
		GetDevices: "/user/devices",
		UnclaimDevice: "/user/devices/:deviceId/unclaim",
		GetDeviceEvents: "/user/devices/:deviceId/events",
		DeleteDeviceEvents: "/user/devices/:deviceId/events",
		SearchDeviceEvents: "/user/devices/:deviceId/events/search",
		GetAllEvents: "/user/events/all",
	},
	Caregiver: {
		_: "/caregiver",
		Claim: "/caregiver/claim-device",
		Remove: "/caregiver/devices/:deviceId/caregiver",
		GetDevices: "/caregiver/devices",
		GetDeviceSummary: "/caregiver/devices/:deviceId/summary",
		SearchDevice: "/caregiver/search/device",
		FilterEvents: "/caregiver/events/filter/date",
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
