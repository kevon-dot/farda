import 'dart:async';

import 'package:farda/consumer_v2/screens/you/farda_circle_screen.dart';
import 'package:farda/features/consumer/data/circle_models.dart';
import 'package:farda/features/consumer/data/consumer_demo_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _permissions = CirclePermissions(doseStatus: true, reminders: false);

CircleMember _member(String id, String name) => CircleMember(
  id: id,
  person: CirclePerson(id: 'person-$id', displayName: name),
  permissions: _permissions,
  acceptedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _CircleRepository extends ConsumerDemoRepository {
  _CircleRepository(
    this.name, {
    this.shared = const [],
    this.failLeave = false,
  });

  final String name;
  final List<SharedCircle> shared;
  final bool failLeave;
  Completer<CircleOverview>? circleCompleter;
  int leaveCalls = 0;
  int inviteCalls = 0;

  @override
  bool get isDemo => false;

  @override
  Future<CircleOverview> loadCircle() =>
      circleCompleter?.future ??
      Future.value(
        CircleOverview(pending: const [], members: [_member(name, name)]),
      );

  @override
  Future<List<CircleInvitation>> loadCircleInvitations() async => const [];

  @override
  Future<List<SharedCircle>> loadSharedCircles() async => shared;

  @override
  Future<CircleInvitation> inviteToCircle(
    String phone,
    CirclePermissions permissions,
  ) async {
    inviteCalls++;
    return CircleInvitation(
      id: 'invite',
      person: const CirclePerson(id: 'recipient', displayName: 'Recipient'),
      permissions: permissions,
      createdAt: DateTime.utc(2026),
      expiresAt: DateTime.utc(2026, 2),
      inviteCode: 'code',
    );
  }

  @override
  Future<CircleRoutine> loadSharedCircleRoutine(
    String grantId, {
    required DateTime from,
    required DateTime to,
  }) async => CircleRoutine(
    owner: shared.single.owner,
    permissions: _permissions,
    items: const [],
    fetchedAt: DateTime.utc(2026),
    notice: 'Shared status',
  );

  @override
  Future<void> leaveSharedCircle(String grantId) async {
    leaveCalls++;
    if (failLeave) throw StateError('revoke failed');
  }
}

Widget _screen(ConsumerDemoRepository? repository) => MaterialApp(
  home: Scaffold(
    body: FardaCircleScreen(
      repository: repository,
      onBack: () {},
      showBrandHeader: false,
    ),
  ),
);

void main() {
  testWidgets(
    'a delayed old repository response cannot replace the new session',
    (tester) async {
      final oldRepository = _CircleRepository('Old family');
      final oldResponse = Completer<CircleOverview>();
      oldRepository.circleCompleter = oldResponse;
      final newRepository = _CircleRepository('New family');

      await tester.pumpWidget(_screen(oldRepository));
      await tester.pump();
      await tester.pumpWidget(_screen(newRepository));
      await tester.pumpAndSettle();

      expect(find.text('New family'), findsOneWidget);
      expect(find.text('Old family'), findsNothing);

      oldResponse.complete(
        CircleOverview(
          pending: const [],
          members: [_member('old', 'Old family')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New family'), findsOneWidget);
      expect(find.text('Old family'), findsNothing);
    },
  );

  testWidgets('logout clears account circle content immediately', (
    tester,
  ) async {
    final repository = _CircleRepository('Private family');
    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();
    expect(find.text('Private family'), findsOneWidget);

    await tester.pumpWidget(_screen(null));
    await tester.pump();

    expect(find.text('Private family'), findsNothing);
    expect(
      find.text('Sign in to invite your family and share your routine.'),
      findsOneWidget,
    );
  });

  testWidgets('invite sheet cannot submit through a replacement session', (
    tester,
  ) async {
    final oldRepository = _CircleRepository('Old family');
    final newRepository = _CircleRepository('New family');
    await tester.pumpWidget(_screen(oldRepository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invite someone'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '+1 555 123 4567');
    await tester.tap(find.text('Dose updates').last);
    await tester.pump();

    await tester.pumpWidget(_screen(newRepository));
    await tester.pump();
    await tester.tap(find.text('Create invitation'));
    await tester.pumpAndSettle();

    expect(oldRepository.inviteCalls, 0);
    expect(newRepository.inviteCalls, 0);
  });

  testWidgets('an older refresh cannot overwrite a newer refresh', (
    tester,
  ) async {
    final repository = _CircleRepository('Initial family');
    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();

    final stale = Completer<CircleOverview>();
    repository.circleCompleter = stale;
    final refresh = find.widgetWithText(TextButton, 'Refresh');
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pump();

    repository.circleCompleter = null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Initial family'), findsOneWidget);

    stale.complete(
      CircleOverview(
        pending: const [],
        members: [_member('stale', 'Stale family')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stale family'), findsNothing);
    expect(find.text('Initial family'), findsOneWidget);
  });

  testWidgets('failed leave keeps the shared routine visible', (tester) async {
    final access = _member('grant', 'Viewer');
    final repository = _CircleRepository(
      'Family',
      failLeave: true,
      shared: [
        SharedCircle(
          access: access,
          owner: const CirclePerson(id: 'owner', displayName: 'Alex'),
        ),
      ],
    );
    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Shared with me'));
    await tester.pump();
    await tester.tap(find.byTooltip('Open shared routine'));
    await tester.pumpAndSettle();
    expect(find.text('Alex’s day'), findsOneWidget);

    final leave = find.text('Leave this circle');
    await tester.ensureVisible(leave);
    await tester.tap(leave);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave circle'));
    await tester.pumpAndSettle();

    expect(repository.leaveCalls, 1);
    expect(find.text('Alex’s day'), findsOneWidget);
    expect(
      find.text('We couldn’t confirm the change. Refresh before trying again.'),
      findsOneWidget,
    );
  });
}
