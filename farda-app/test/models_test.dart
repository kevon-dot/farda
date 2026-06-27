// Pure-Dart unit tests for the data models. These import only model files
// (no widgets, plugins, or platform channels) so they run fast and reliably
// under `flutter test` in CI.

import 'package:flutter_test/flutter_test.dart';

import 'package:farda/application/prescription/model/prescription_model.dart';
import 'package:farda/application/calender/model/mood_model.dart';
import 'package:farda/screens/login/login_provider.dart';
import 'package:farda/screens/prescription_info/prescription_provider.dart';

void main() {
  group('PrescriptionModel', () {
    test('fromJson maps snake_case keys and nested medicines', () {
      final model = PrescriptionModel.fromJson({
        'pharmacy_or_doctor_name': 'Dr. Smith',
        'rx_number': 'RX-100',
        'store_number': 'S-7',
        'deviceId': 'vial-abc',
        'medicines_names': [
          {'medicine_name': 'Amoxicillin', 'qty': '30', 'instructions': '1/day'}
        ],
      });

      expect(model.pharmacyOrDoctorName, 'Dr. Smith');
      expect(model.rxNumber, 'RX-100');
      expect(model.storeNumber, 'S-7');
      expect(model.deviceId, 'vial-abc');
      expect(model.medicinesNames, isNotNull);
      expect(model.medicinesNames!.length, 1);
      expect(model.medicinesNames!.first.medicineName, 'Amoxicillin');
    });

    test('fromJson also accepts the "medicines" key', () {
      final model = PrescriptionModel.fromJson({
        'medicines': [
          {'medicine_name': 'Ibuprofen'}
        ],
      });
      expect(model.medicinesNames!.first.medicineName, 'Ibuprofen');
    });

    test('toSubmit nests userId and medicines_names', () {
      final model = PrescriptionModel(
        rxNumber: 'RX-1',
        medicinesNames: [MedicinesNames(medicineName: 'Med A', qty: '10')],
      );
      final submit = model.toSubmit('user-42');

      expect(submit['userId'], 'user-42');
      expect(submit['rx_number'], 'RX-1');
      expect(submit['medicines_names'], isA<List>());
      expect((submit['medicines_names'] as List).first['medicine_name'], 'Med A');
    });

    test('round-trips through toJson/fromJson', () {
      final original = PrescriptionModel(
        rxNumber: 'RX-9',
        address: '1 Main St',
        dob: '1990-01-01',
        medicinesNames: [MedicinesNames(medicineName: 'Med B', instructions: '2/day')],
      );
      final copy = PrescriptionModel.fromJson(original.toJson());

      expect(copy.rxNumber, 'RX-9');
      expect(copy.address, '1 Main St');
      expect(copy.dob, '1990-01-01');
      expect(copy.medicinesNames!.first.medicineName, 'Med B');
      expect(copy.medicinesNames!.first.instructions, '2/day');
    });

    test('toSubmit includes dob', () {
      final model = PrescriptionModel(rxNumber: 'RX-1', dob: '1985-12-31');
      final submit = model.toSubmit('user-42');

      expect(submit['dob'], '1985-12-31');
    });
  });

  group('PrescriptionProvider.syncControllersToModel', () {
    test(
        'merges manually edited Rx#/store#/pill-qty/DOB into the submit payload',
        () {
      final provider = PrescriptionProvider();

      // Simulate OCR having pre-filled the model with some values.
      provider.prescriptionModel = PrescriptionModel(
        rxNumber: 'OCR-RX',
        storeNumber: 'OCR-STORE',
        medicinesNames: [MedicinesNames(medicineName: 'Med A', qty: '5')],
      );

      // The user then manually edits every field on the form.
      provider.prescriptionNumberController.text = '1234567';
      provider.storeNumberController.text = '4321';
      provider.pillQtyController.text = '30';
      provider.dobController.text = '1990-06-15';

      provider.syncControllersToModel();
      final submit = provider.prescriptionModel.toSubmit('user-7');

      // Manual edits override the OCR-extracted values in the payload.
      expect(submit['rx_number'], '1234567');
      expect(submit['store_number'], '4321');
      expect(submit['dob'], '1990-06-15');
      expect(
        (submit['medicines_names'] as List).first['qty'],
        '30',
      );
    });

    test('blank fields fall back to existing OCR values', () {
      final provider = PrescriptionProvider();
      provider.prescriptionModel = PrescriptionModel(
        rxNumber: 'OCR-RX',
        storeNumber: 'OCR-STORE',
        dob: '2000-01-01',
      );

      // Leave all controllers empty.
      provider.syncControllersToModel();
      final submit = provider.prescriptionModel.toSubmit('user-7');

      expect(submit['rx_number'], 'OCR-RX');
      expect(submit['store_number'], 'OCR-STORE');
      expect(submit['dob'], '2000-01-01');
    });
  });

  group('LoginProvider.displayNameFromResponse', () {
    test('returns the user name from a verify-otp response', () {
      final name = LoginProvider.displayNameFromResponse({
        'status': true,
        'token': 'abc',
        'user': {'id': 'u-1', 'name': 'Jane Doe'},
      });
      expect(name, 'Jane Doe');
    });

    test('trims surrounding whitespace', () {
      final name = LoginProvider.displayNameFromResponse({
        'user': {'name': '  Jane Doe  '},
      });
      expect(name, 'Jane Doe');
    });

    test('returns empty string when name is missing', () {
      expect(
        LoginProvider.displayNameFromResponse({'user': {'id': 'u-1'}}),
        '',
      );
    });

    test('returns empty string when name is blank', () {
      expect(
        LoginProvider.displayNameFromResponse({'user': {'name': '   '}}),
        '',
      );
    });

    test('returns empty string when user is absent or response is null', () {
      expect(LoginProvider.displayNameFromResponse({'status': true}), '');
      expect(LoginProvider.displayNameFromResponse(null), '');
    });
  });

  group('MoodModel', () {
    test('round-trips through toJson/fromJson', () {
      final mood = MoodModel(date: '2026-06-27', emoji: 'calm', user: 7);
      final copy = MoodModel.fromJson(mood.toJson());

      expect(copy.date, '2026-06-27');
      expect(copy.emoji, 'calm');
      expect(copy.user, 7);
    });
  });
}
