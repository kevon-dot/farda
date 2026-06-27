// Pure-Dart unit tests for the Vial-API wiring (issue #14/#30, app-calls-both).
//
// These import only pure helpers (URL/endpoint builders, payload builders, and
// the env getter) — no widgets, plugins, or platform channels — so they run
// fast and reliably under `flutter test` in CI.

import 'package:flutter_test/flutter_test.dart';

import 'package:farda/app_const/app_urls.dart';
import 'package:farda/application/caregiver/repo/caregiver_repo.dart';
import 'package:farda/application/device/repo/device_repo.dart';
import 'package:farda/utilities/api_service.dart';

void main() {
  group('ApiService.buildUri', () {
    test('joins base + endpoint with exactly one slash', () {
      final uri = ApiService.buildUri('https://vial.example', 'api/user/claim');
      expect(uri.toString(), 'https://vial.example/api/user/claim');
    });

    test('tolerates a trailing slash on the base', () {
      final uri = ApiService.buildUri('https://vial.example/', 'api/user/claim');
      expect(uri.toString(), 'https://vial.example/api/user/claim');
    });

    test('tolerates a leading slash on the endpoint', () {
      final uri = ApiService.buildUri('https://vial.example', '/api/user/claim');
      expect(uri.toString(), 'https://vial.example/api/user/claim');
    });

    test('does not collapse a double slash from base + endpoint', () {
      final uri =
          ApiService.buildUri('https://vial.example/', '/api/user/claim');
      expect(uri.toString(), 'https://vial.example/api/user/claim');
    });
  });

  group('VialUrls — paths mirror the Vial Express routers', () {
    test('static device + user paths', () {
      expect(VialUrls.saveUser, 'api/user/save');
      expect(VialUrls.claimDevice, 'api/user/claim');
      expect(VialUrls.userDevices, 'api/user/devices');
      expect(VialUrls.allDevicesEvents, 'api/user/events/all');
    });

    test('parameterised device event paths', () {
      expect(VialUrls.deviceEvents('vial-1'), 'api/user/devices/vial-1/events');
      expect(VialUrls.deviceEventsSearch('vial-1'),
          'api/user/devices/vial-1/events/search');
      expect(VialUrls.unclaimDevice('vial-1'),
          'api/user/devices/vial-1/unclaim');
      expect(VialUrls.deleteDeviceEvents('vial-1'),
          'api/user/devices/vial-1/events');
      expect(VialUrls.deleteCaregiverAccess('vial-1'),
          'api/user/devices/vial-1/caregiver');
    });

    test('device ids are URL-encoded', () {
      // A space (or any unsafe char) must not break the path segment.
      expect(VialUrls.deviceEvents('a b'), 'api/user/devices/a%20b/events');
    });

    test('caregiver paths', () {
      expect(VialUrls.caregiverClaimDevice, 'api/caregiver/claim-device');
      expect(VialUrls.caregiverDevices, 'api/caregiver/devices');
      expect(VialUrls.caregiverDeviceSummary('vial-1'),
          'api/caregiver/devices/vial-1/summary');
      expect(VialUrls.caregiverSearchDevice, 'api/caregiver/search/device');
      expect(VialUrls.caregiverEventsByDate, 'api/caregiver/events/filter/date');
    });
  });

  group('request body builders', () {
    test('DeviceRepo.buildClaimBody uses the device_id key', () {
      final body = DeviceRepo.buildClaimBody('vial-9');
      expect(body, {'device_id': 'vial-9'});
    });

    test('CaregiverRepo.buildAssignCaregiverBody carries both ids', () {
      final body =
          CaregiverRepo.buildAssignCaregiverBody('vial-9', 'caregiver-7');
      expect(body, {'device_id': 'vial-9', 'caregiver_id': 'caregiver-7'});
    });
  });

  group('Vial URL composition', () {
    test('a full Vial claim URL composes correctly from base + endpoint', () {
      final uri = ApiService.buildUri(
        'https://vial.example',
        VialUrls.claimDevice,
      );
      expect(uri.toString(), 'https://vial.example/api/user/claim');
    });
  });
}
