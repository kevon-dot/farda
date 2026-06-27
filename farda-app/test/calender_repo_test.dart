// Pure-Dart unit tests for the calendar note-submission payload. This imports
// only the repo file (no widgets, plugins, or platform channels) so it runs
// fast and reliably under `flutter test` in CI.

import 'package:flutter_test/flutter_test.dart';

import 'package:farda/application/calender/repo/calender_repo.dart';

void main() {
  group('CalenderRepo.buildNotePayload', () {
    test('uses the provided note text, not a hardcoded value', () {
      final payload = CalenderRepo.buildNotePayload('dose-1', 'Felt great today');

      expect(payload['dose_time_id'], 'dose-1');
      expect(payload['note'], 'Felt great today');
      // Guards against the previous bug where the body hardcoded "dsfasd".
      expect(payload['note'], isNot('dsfasd'));
    });

    test('round-trips an empty note without substituting a default', () {
      final payload = CalenderRepo.buildNotePayload('dose-2', '');

      expect(payload['dose_time_id'], 'dose-2');
      expect(payload['note'], '');
    });
  });
}
