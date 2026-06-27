class PrescriptionModel {
  String? pharmacyOrDoctorName;
  String? contactDetails;
  String? dateFilled;
  String? dateExpired;
  String? address;
  String? rxNumber;
  String? storeNumber;
  String? deviceId;
  List<MedicinesNames>? medicinesNames;

  PrescriptionModel(
      {this.pharmacyOrDoctorName,
      this.contactDetails,
      this.dateFilled,
      this.dateExpired,
      this.address,
      this.rxNumber,
      this.storeNumber,
      this.deviceId,
      this.medicinesNames});

  PrescriptionModel.fromJson(Map<String, dynamic> json) {
    pharmacyOrDoctorName = json['pharmacy_or_doctor_name'];
    contactDetails = json['contact_details'];
    dateFilled = json['date_filled'];
    dateExpired = json['date_expired'];
    address = json['address'];
    rxNumber = json['rx_number'];
    storeNumber = json['store_number'];
    deviceId = json['deviceId'];
    
    // Check both 'medicines' and 'medicines_names' keys for compatibility
    final medicinesList = json['medicines'] ?? json['medicines_names'];
    if (medicinesList != null) {
      medicinesNames = <MedicinesNames>[];
      medicinesList.forEach((v) {
        medicinesNames!.add(new MedicinesNames.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['pharmacy_or_doctor_name'] = pharmacyOrDoctorName;
    data['contact_details'] = contactDetails;
    data['date_filled'] = dateFilled;
    data['date_expired'] = dateExpired;
    data['address'] = address;
    data['rx_number'] = rxNumber;
    data['store_number'] = storeNumber;
    data['deviceId'] = deviceId;
    if (medicinesNames != null) {
      data['medicines'] =
          medicinesNames!.map((v) => v.toJson()).toList();
    }
    return data;
  }
  Map<String, dynamic> toSubmit(String userId) {
    return {
      "userId": userId,
      "pharmacy_or_doctor_name": pharmacyOrDoctorName,
      "contact_details": contactDetails,
      "date_filled": dateFilled,
      "date_expired": dateExpired,
      "address": address,
      "rx_number": rxNumber,
      "store_number": storeNumber,
      "deviceId": deviceId,
      "medicines_names": medicinesNames?.map((m) => m.toMedicineName()).toList() ?? [],
    };
  }
}

class MedicinesNames {
  String? medicineName;
  String? genericName;
  String? instructions;
  dynamic qty;
  String? refillsInfo;
  String? sideEffects;

  MedicinesNames(
      {this.medicineName,
      this.genericName,
      this.instructions,
      this.qty,
      this.refillsInfo,
      this.sideEffects});

  MedicinesNames.fromJson(Map<String, dynamic> json) {
    medicineName = json['medicine_name'];
    genericName = json['generic_name'];
    instructions = json['instructions'];
    qty = json['qty'];
    refillsInfo = json['refills_info'];
    sideEffects = json['side_effects'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['medicine_name'] = medicineName;
    data['generic_name'] = genericName;
    data['instructions'] = instructions;
    data['qty'] = qty;
    data['refills_info'] = refillsInfo;
    data['side_effects'] = sideEffects;
    return data;
  }

  Map<String, dynamic> toMedicineName() => {
  "medicine_name": medicineName,
  "generic_name": genericName,
  "instructions": instructions,
  "qty": qty,
  "refills_info" : refillsInfo,
  "side_effects": sideEffects,
  
};

}
