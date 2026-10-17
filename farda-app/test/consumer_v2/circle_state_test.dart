import 'dart:async';
import 'package:farda/application/authentication/storage/auth_storage.dart';

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
    this.routinePermissions = _permissions,
    this.items = const [],
    this.invitations = const [],
  });

  final String name;
  final List<SharedCircle> shared;
  final bool failLeave;
  final CirclePermissions routinePermissions;
  final List<CircleRoutineItem> items;
  final List<CircleInvitation> invitations;
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
  Future<List<CircleInvitation>> loadCircleInvitations() async => invitations;

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
    permissions: routinePermissions,
    items: items,
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
    'same repository session revision clears Circle and rejects pending refresh',
    (tester) async {
      final repo = _CircleRepository('Private family');
      await tester.pumpWidget(_screen(repo));
      await tester.pumpAndSettle();
      expect(find.text('Private family'), findsOneWidget);
      final response = Completer<CircleOverview>();
      repo.circleCompleter = response;
      await tester.ensureVisible(find.text('Refresh'));
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      AuthStorage.sessionRevision.value++;
      await tester.pump();
      response.complete(
        CircleOverview(
          pending: const [],
          members: [_member('private', 'Private family')],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private family'), findsNothing);
      expect(
        find.text('Your account changed. Reopen your circle to continue.'),
        findsOneWidget,
      );
    },
  );

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
    await tester.pumpAndSettle();
    expect(find.text('Create invitation'), findsNothing);

    expect(oldRepository.inviteCalls, 0);
    expect(newRepository.inviteCalls, 0);
  });

  testWidgets(
    'account revision dismisses invitation details and disables old-session actions',
    (tester) async {
      final repository = _CircleRepository('Private family');
      await tester.pumpWidget(_screen(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invite someone'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '+15551234567');
      AuthStorage.sessionRevision.value++;
      await tester.pumpAndSettle();
      expect(find.text('+15551234567'), findsNothing);
      expect(find.text('Create invitation'), findsNothing);
      final invite = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Invite someone'),
      );
      expect(invite.onPressed, isNull);
      expect(find.text('Back to You'), findsOneWidget);
      expect(repository.inviteCalls, 0);
    },
  );

  testWidgets(
    'account revision removes nested access confirmation and management sheet',
    (tester) async {
      final repository = _CircleRepository('Private family');
      await tester.pumpWidget(_screen(repository));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Manage sharing'));
      await tester.tap(find.byTooltip('Manage sharing'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Remove from my circle'));
      await tester.tap(find.text('Remove from my circle'));
      await tester.pumpAndSettle();
      expect(find.text('Remove access?'), findsOneWidget);
      AuthStorage.sessionRevision.value++;
      await tester.pumpAndSettle();
      expect(find.text('Remove access?'), findsNothing);
      expect(find.text('Sharing with Private family'), findsNothing);
      expect(find.text('Private family'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared routine hides stale reminder times and all items when sharing pauses',
    (tester) async {
      for (final doses in [true, false]) {
        final repository = _CircleRepository(
          'Family',
          routinePermissions: CirclePermissions(
            doseStatus: doses,
            reminders: false,
          ),
          shared: [
            SharedCircle(
              access: _member('grant', 'Viewer'),
              owner: const CirclePerson(id: 'owner', displayName: 'Sam'),
            ),
          ],
          items: [
            CircleRoutineItem(
              id: 'private',
              label: 'Private routine item',
              scheduledFor: DateTime(2026, 10, 17, 13, 37),
              state: CircleRoutineState.taken,
              evidence: CircleEvidence.selfReport,
            ),
          ],
        );
        await tester.pumpWidget(_screen(repository));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.textContaining('Shared with me'));
        await tester.tap(find.textContaining('Shared with me'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('Open shared routine'));
        await tester.tap(find.byTooltip('Open shared routine'));
        await tester.pumpAndSettle();
        expect(find.text('1:37 PM'), findsNothing);
        expect(
          find.text('Private routine item'),
          doses ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Reported taken'),
          doses ? findsOneWidget : findsNothing,
        );
      }
    },
  );

  testWidgets(
    'acceptance reviews permissions and prevents empty or expired code submission',
    (tester) async {
      for (final expired in [false, true]) {
        final repository = _CircleRepository(
          'Family',
          invitations: [
            CircleInvitation(
              id: 'invite',
              person: const CirclePerson(id: 'owner', displayName: 'Sam'),
              permissions: _permissions,
              createdAt: DateTime(2000),
              expiresAt: DateTime(expired ? 2001 : 2099),
            ),
          ],
        );
        await tester.pumpWidget(_screen(repository));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.textContaining('Shared with me'));
        await tester.tap(find.textContaining('Shared with me'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Review'));
        await tester.tap(find.text('Review'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'You’ll be able to view dose updates. Reminder times stay private.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Joining does not share your own routine. You can leave anytime.',
          ),
          findsOneWidget,
        );
        final accept = find.widgetWithText(FilledButton, 'Accept invitation');
        expect(tester.widget<FilledButton>(accept).onPressed, isNull);
        await tester.enterText(find.byType(TextField), 'invitation-code');
        await tester.pump();
        expect(
          tester.widget<FilledButton>(accept).onPressed,
          expired ? isNull : isNotNull,
        );
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
      }
    },
  );

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
