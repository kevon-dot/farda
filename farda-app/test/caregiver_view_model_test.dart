// GTM-517 — pure-Dart unit tests for the caregiver/patient view-model + models.
// Imports only model + view-model files (no widgets, plugins, or platform
// channels) so they run fast and reliably under `flutter test` in CI.

import 'package:flutter_test/flutter_test.dart';

import 'package:farda/application/caregiver/model/caregiver_device_summary_model.dart';
import 'package:farda/application/caregiver/model/caregiver_grant_model.dart';
import 'package:farda/screens/caregiver/caregiver_view_model.dart';

CaregiverGrantModel _grant({
  String? id,
  String? deviceId,
  String? patient,
  String? caregiver,
  required String status,
}) {
  return CaregiverGrantModel(
    id: id,
    deviceId: deviceId,
    patientUserId: patient,
    caregiverUserId: caregiver,
    status: status,
  );
}

void main() {
  group('CaregiverGrants.fromJson', () {
    test('parses both buckets and snake_case fields', () {
      final grants = CaregiverGrants.fromJson({
        'as_caregiver': [
          {
            'id': 'g1',
            'device_id': 'D1',
            'patient_user_id': 'owner_1',
            'caregiver_user_id': 'me',
            'status': 'pending',
            'invited_at': '2026-06-01T00:00:00Z',
          },
        ],
        'as_owner': [
          {'id': 'g2', 'caregiver_user_id': 'cg_x', 'status': 'accepted'},
        ],
      });

      expect(grants.asCaregiver.length, 1);
      expect(grants.asOwner.length, 1);
      expect(grants.asCaregiver.first.deviceId, 'D1');
      expect(grants.asCaregiver.first.isPending, isTrue);
      expect(grants.asOwner.first.isAccepted, isTrue);
    });

    test('tolerates missing/empty buckets', () {
      final grants = CaregiverGrants.fromJson({});
      expect(grants.isEmpty, isTrue);
      expect(grants.asCaregiver, isEmpty);
      expect(grants.asOwner, isEmpty);
    });
  });

  group('CaregiverViewModel partitioning', () {
    final grants = CaregiverGrants(
      asCaregiver: [
        _grant(id: 'a', deviceId: 'D1', status: CaregiverGrantStatus.pending),
        _grant(id: 'b', deviceId: 'D2', status: CaregiverGrantStatus.accepted),
        _grant(id: 'c', deviceId: 'D3', status: CaregiverGrantStatus.revoked),
      ],
      asOwner: [
        _grant(id: 'd', caregiver: 'cg1', status: CaregiverGrantStatus.pending),
        _grant(id: 'e', caregiver: 'cg2', status: CaregiverGrantStatus.accepted),
      ],
    );

    test('pendingInvitesForMe returns only my pending caregiver grants', () {
      final r = CaregiverViewModel.pendingInvitesForMe(grants);
      expect(r.map((g) => g.id), ['a']);
    });

    test('authorizedPatients returns ONLY accepted grants (pending excluded)', () {
      final r = CaregiverViewModel.authorizedPatients(grants);
      // Server-authoritative invariant: a pending/revoked grant must never
      // surface as an authorized patient.
      expect(r.map((g) => g.id), ['b']);
    });

    test('outstandingInvitesFromMe returns only my pending owner grants', () {
      final r = CaregiverViewModel.outstandingInvitesFromMe(grants);
      expect(r.map((g) => g.id), ['d']);
    });

    test('myAcceptedCaregivers returns only my accepted owner grants', () {
      final r = CaregiverViewModel.myAcceptedCaregivers(grants);
      expect(r.map((g) => g.id), ['e']);
    });
  });

  group('CaregiverViewModel.buildInviteBody / canSubmitInvite', () {
    test('builds a trimmed invite body', () {
      final body = CaregiverViewModel.buildInviteBody('  D1 ', ' cg_1 ');
      expect(body, {'device_id': 'D1', 'caregiver_id': 'cg_1'});
    });

    test('canSubmitInvite requires both ids', () {
      expect(
        CaregiverViewModel.canSubmitInvite(deviceId: 'D1', caregiverId: 'cg'),
        isTrue,
      );
      expect(
        CaregiverViewModel.canSubmitInvite(deviceId: '  ', caregiverId: 'cg'),
        isFalse,
      );
      expect(
        CaregiverViewModel.canSubmitInvite(deviceId: 'D1', caregiverId: ''),
        isFalse,
      );
    });

    test('canSubmitInvite blocks inviting yourself', () {
      expect(
        CaregiverViewModel.canSubmitInvite(
          deviceId: 'D1',
          caregiverId: 'me',
          ownerUserId: 'me',
        ),
        isFalse,
      );
    });
  });

  group('CaregiverViewModel.doseStatus', () {
    CaregiverDeviceSummary summaryWithOpen(String? iso) {
      return CaregiverDeviceSummary(
        deviceId: 'D1',
        recentEvents: [
          if (iso != null)
            {'event_type': 'OPEN', 'device_timestamp': iso},
        ],
      );
    }

    final now = DateTime.parse('2026-06-27T12:00:00Z');

    test('onTrack when last open is within the window', () {
      final s = summaryWithOpen('2026-06-27T06:00:00Z'); // 6h ago
      expect(
        CaregiverViewModel.doseStatus(s, now: now),
        DoseAlertStatus.onTrack,
      );
    });

    test('missedOrLate when last open is older than the window', () {
      final s = summaryWithOpen('2026-06-25T06:00:00Z'); // ~2 days ago
      expect(
        CaregiverViewModel.doseStatus(s, now: now),
        DoseAlertStatus.missedOrLate,
      );
    });

    test('unknown when there are no OPEN events', () {
      final s = summaryWithOpen(null);
      expect(
        CaregiverViewModel.doseStatus(s, now: now),
        DoseAlertStatus.unknown,
      );
    });

    test('ignores non-OPEN events when finding the last open', () {
      final s = CaregiverDeviceSummary(
        deviceId: 'D1',
        recentEvents: [
          {'event_type': 'BATTERY', 'device_timestamp': '2026-06-27T11:00:00Z'},
          {'event_type': 'OPEN', 'device_timestamp': '2026-06-20T11:00:00Z'},
        ],
      );
      expect(
        CaregiverViewModel.doseStatus(s, now: now),
        DoseAlertStatus.missedOrLate,
      );
    });

    test('falls back to server_timestamp when device_timestamp is absent', () {
      final s = CaregiverDeviceSummary(
        deviceId: 'D1',
        recentEvents: [
          {'event_type': 'OPEN', 'server_timestamp': '2026-06-27T08:00:00Z'},
        ],
      );
      final last = CaregiverViewModel.lastOpenAt(s);
      expect(last, DateTime.parse('2026-06-27T08:00:00Z'));
    });
  });

  group('CaregiverDeviceSummary.fromJson', () {
    test('parses the list-endpoint flat shape', () {
      final s = CaregiverDeviceSummary.fromJson({
        'device_id': 'D1',
        'device_name': 'Kitchen vial',
        'battery_percent': 80,
        'is_online': true,
        'last_seen': '2026-06-27T10:00:00Z',
        'recent_events': [
          {'event_type': 'OPEN'},
        ],
        'total_events': 5,
      });
      expect(s.deviceId, 'D1');
      expect(s.deviceName, 'Kitchen vial');
      expect(s.batteryPercent, 80);
      expect(s.isOnline, isTrue);
      expect(s.recentEvents.length, 1);
      expect(s.totalEvents, 5);
    });

    test('parses the single-summary nested device shape', () {
      final s = CaregiverDeviceSummary.fromJson({
        'device': {'device_id': 'D2', 'is_online': false},
        'recent_events': [],
        'total_events': 0,
      });
      expect(s.deviceId, 'D2');
      expect(s.isOnline, isFalse);
    });
  });
}
