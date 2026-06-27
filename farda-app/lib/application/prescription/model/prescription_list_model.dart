class PrescriptionModelList {
  int? id;
  String? rxNumber;
  String? departmentNumber;
  String? dob;
  String? pharmacyOrDoctorName;
  String? contactDetails;
  String? dateFilled;
  String? dateExpired;
  String? address;
  String? storeNumber;
  String? rxImage;
  String? createdAt;
  List<Medicines>? medicines;

  PrescriptionModelList(
      {this.id,
      this.rxNumber,
      this.departmentNumber,
      this.dob,
      this.pharmacyOrDoctorName,
      this.contactDetails,
      this.dateFilled,
      this.dateExpired,
      this.address,
      this.storeNumber,
      this.rxImage,
      this.createdAt,
      this.medicines});

  PrescriptionModelList.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    rxNumber = json['rx_number'];
    departmentNumber = json['department_number'];
    dob = json['dob'];
    pharmacyOrDoctorName = json['pharmacy_or_doctor_name'];
    contactDetails = json['contact_details'];
    dateFilled = json['date_filled'];
    dateExpired = json['date_expired'];
    address = json['address'];
    storeNumber = json['store_number'];
    rxImage = json['rx_image'];
    createdAt = json['created_at'];
    if (json['medicines'] != null) {
      medicines = <Medicines>[];
      json['medicines'].forEach((v) {
        medicines!.add( Medicines.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data =  <String, dynamic>{};
    data['id'] = id;
    data['rx_number'] = rxNumber;
    data['department_number'] = departmentNumber;
    data['dob'] = dob;
    data['pharmacy_or_doctor_name'] = pharmacyOrDoctorName;
    data['contact_details'] = contactDetails;
    data['date_filled'] = dateFilled;
    data['date_expired'] = dateExpired;
    data['address'] = address;
    data['store_number'] = storeNumber;
    data['rx_image'] = rxImage;
    data['created_at'] = createdAt;
    if (medicines != null) {
      data['medicines'] = medicines!.map((v) => v.toJson()).toList();
    }
    return data;
  }
}

class Medicines {
  int? id;
  String? medicineName;
  String? genericName;
  String? instructions;
  String? qty;
  String? refillsInfo;
  String? sideEffects;
  int? prescription;

  Medicines(
      {this.id,
      this.medicineName,
      this.genericName,
      this.instructions,
      this.qty,
      this.refillsInfo,
      this.sideEffects,
      this.prescription});

  Medicines.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    medicineName = json['medicine_name'];
    genericName = json['generic_name'];
    instructions = json['instructions'];
    qty = json['qty'];
    refillsInfo = json['refills_info'];
    sideEffects = json['side_effects'];
    prescription = json['prescription'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['medicine_name'] = medicineName;
    data['generic_name'] = genericName;
    data['instructions'] = instructions;
    data['qty'] = qty;
    data['refills_info'] = refillsInfo;
    data['side_effects'] = sideEffects;
    data['prescription'] = prescription;
    return data;
  }
}
