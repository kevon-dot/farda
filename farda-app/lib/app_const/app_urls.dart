class AppUrls {
  static String getDoseTime = "dosetime/";
  static String getExtractPrescriptionOcr = "prescriptions/ocr/extract";
  static String getPrescription = "my-prescriptions/";
  static String submitPrescription = "prescriptions/ocr/save";
  static String getMode = "mood/";
  static String setMood = "mood/";
  static String setNotes = "dose-notes/";

  // --- Backend Paths ---
  static const String api = "/api";

  // Users
  static const String usersPath = "/users";
  static const String usersGetAll = "/users/all";
  static const String usersAdd = "/users/add";
  static const String usersUpdate = "/users/update";
  static String usersDelete(String id) => "/users/delete/$id";

  // Auth
  static const String authPath = "/auth";
  static const String authSendOTP = "/auth/send-otp";
  static const String authVerifyOTP = "/auth/verify-otp";

  // DeviceUser
  static const String userPath = "/user";
  static const String userClaim = "/user/claim";
  static const String userGetDevices = "/user/devices";
  static String userUnclaimDevice(String deviceId) =>
      "/user/devices/$deviceId/unclaim";
  static String userGetDeviceEvents(String deviceId) =>
      "/user/devices/$deviceId/events";
  static String userDeleteDeviceEvents(String deviceId) =>
      "/user/devices/$deviceId/events";
  static String userSearchDeviceEvents(String deviceId) =>
      "/user/devices/$deviceId/events/search";
  static const String userGetAllEvents = "/user/events/all";

  // Caregiver
  static const String caregiverPath = "/caregiver";
  static const String caregiverClaim = "/caregiver/claim-device";
  static String caregiverRemove(String deviceId) =>
      "/caregiver/devices/$deviceId/caregiver";
  static const String caregiverGetDevices = "/caregiver/devices";
  static String caregiverGetDeviceSummary(String deviceId) =>
      "/caregiver/devices/$deviceId/summary";
  static const String caregiverSearchDevice = "/caregiver/search/device";
  static const String caregiverFilterEvents = "/caregiver/events/filter/date";
}
