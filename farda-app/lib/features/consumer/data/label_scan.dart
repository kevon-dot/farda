import 'dart:typed_data';

import 'consumer_models.dart';

/// Images stay in this capture session; upload occurs only on Review label.
class LabelPhoto {
  const LabelPhoto({required this.bytes, required this.mimeType});
  final Uint8List bytes;
  final String mimeType;

  static String? detectMime(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes.take(8).join(',') == '137,80,78,71,13,10,26,10') {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }

  String? get validationError {
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      return 'Choose a photo under 8 MB, or take a new photo.';
    }
    if (detectMime(bytes) != mimeType) {
      return 'Choose a JPEG, PNG or WebP image, or take a new photo.';
    }
    return null;
  }
}

/// OCR is a transcription draft, never approval or evidence of completeness.
class LabelScanDraft {
  const LabelScanDraft({
    this.medicationName,
    this.directions,
    this.pharmacy,
    this.rxNumber,
    this.manualEntry = false,
  });
  final String? medicationName;
  final String? directions;
  final String? pharmacy;
  final String? rxNumber;
  final bool manualEntry;

  factory LabelScanDraft.fromJson(Map<String, dynamic> json) {
    final medicines = json['medicines_names'];
    if (medicines is! List ||
        medicines.length != 1 ||
        medicines.single is! Map) {
      throw const ConsumerRepositoryException(
        'We could not identify one medication. Photograph one label at a time, or enter it manually.',
      );
    }
    String? field(Object? value) {
      if (value == null) return null;
      if (value is! String) throw const FormatException('Invalid label field');
      return value.trim().isEmpty ? null : value;
    }

    final medicine = medicines.single as Map;
    return LabelScanDraft(
      medicationName: field(medicine['medicine_name']),
      directions: field(medicine['instructions']),
      pharmacy: field(json['pharmacy_or_doctor_name']),
      rxNumber: field(json['rx_number']),
    );
  }
}

/// Optional capability: demo repositories must never simulate a real scan.
abstract interface class LabelScanRepository {
  Future<LabelScanDraft> extractLabel(List<LabelPhoto> photos);
}
