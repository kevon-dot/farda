import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'dart:async';
import 'package:farda/consumer_v2/screens/refills/pharmacy_handoff_card.dart';
import 'package:farda/features/consumer/data/pharmacy_handoff.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final cvs = PharmacyDestination(
  id: 'cvs',
  name: 'CVS',
  aliases: ['CVS Pharmacy'],
  actions: {'refill': Uri.parse('https://www.cvs.com/pharmacy/')},
);

class FakePharmacy implements PharmacyHandoffRepository {
  bool sessionValid = true;
  bool malicious = false;
  Completer<PharmacyHandoff>? pending;
  @override
  Future<Future<bool> Function()> capturePharmacySession() async =>
      () async => sessionValid;
  @override
  Future<List<PharmacyDestination>> loadPharmacyDirectory() async => [cvs];
  @override
  Future<PharmacyHandoff> preparePharmacyHandoff(
    String id, {
    required String pharmacyId,
    required String purpose,
  }) async =>
      pending?.future ??
      PharmacyHandoff(
        pharmacyId: pharmacyId,
        pharmacyName: 'CVS',
        purpose: purpose,
        mode: purpose == 'refill' ? 'external_site' : 'call_prescriber',
        notice:
            purpose == 'refill'
                ? 'Complete your request on the pharmacy website.'
                : 'Ask your prescriber for a renewal.',
        url:
            purpose != 'refill'
                ? null
                : malicious
                ? Uri.parse('https://evil.example/')
                : cvs.actions['refill'],
      );
}

Future<void> pump(
  WidgetTester tester,
  FakePharmacy repo, {
  Future<bool> Function(Uri)? open,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PharmacyHandoffCard(
            prescriptionId: 'rx1',
            repository: repo,
            medicationName: 'Example medication',
            rxNumber: '123456',
            savedPharmacy: 'CVS Pharmacy',
            openUrl: open,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'destination rejects PHI query, foreign host and mismatched purpose',
    () {
      for (final value in [
        'https://www.cvs.com/pharmacy/?rx=123',
        'https://evil.example/',
        'http://www.cvs.com/pharmacy/',
      ]) {
        expect(
          PharmacyHandoff(
            pharmacyId: 'cvs',
            pharmacyName: 'CVS',
            purpose: 'refill',
            mode: 'external_site',
            notice: '',
            url: Uri.parse(value),
          ).hasSafeDestination(cvs),
          isFalse,
        );
      }
      expect(cvs.matches('CVS Pharmacy'), isTrue);
      expect(cvs.matches('not CVS'), isFalse);
    },
  );
  testWidgets('account change clears details and discards pending handoff', (
    tester,
  ) async {
    final repo = FakePharmacy()..pending = Completer<PharmacyHandoff>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PharmacyHandoffCard(
            prescriptionId: 'rx1',
            repository: repo,
            medicationName: 'Private medication',
            rxNumber: '123456',
            savedPharmacy: 'CVS',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    AuthStorage.sessionRevision.value++;
    await tester.pump();
    repo.pending!.complete(
      PharmacyHandoff(
        pharmacyId: 'cvs',
        pharmacyName: 'CVS',
        purpose: 'refill',
        mode: 'external_site',
        notice: 'Continue',
        url: cvs.actions['refill'],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private medication'), findsNothing);
    expect(find.byKey(const Key('pharmacy-continue')), findsNothing);
  });

  testWidgets('handoff opens only after tap and copy is explicit', (
    tester,
  ) async {
    final repo = FakePharmacy();
    final opened = <Uri>[];
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pump(
      tester,
      repo,
      open: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    expect(opened, isEmpty);
    expect(copied, isEmpty);
    await tester.tap(find.byKey(const Key('pharmacy-copy-rx')));
    await tester.pumpAndSettle();
    expect(copied, ['123456']);
    await tester.ensureVisible(find.byKey(const Key('pharmacy-continue')));
    await tester.tap(find.byKey(const Key('pharmacy-continue')));
    await tester.pumpAndSettle();
    expect(opened.single, cvs.actions['refill']);
    expect(opened.single.hasQuery, isFalse);
    expect(
      find.text(
        'Nothing is sent from Farda. Sign in and complete your request there.',
      ),
      findsOneWidget,
    );
  });
  testWidgets('changed session blocks browser and hides destination', (
    tester,
  ) async {
    final repo = FakePharmacy();
    var opens = 0;
    await pump(
      tester,
      repo,
      open: (_) async {
        opens++;
        return true;
      },
    );
    repo.sessionValid = false;
    await tester.ensureVisible(find.byKey(const Key('pharmacy-continue')));
    await tester.tap(find.byKey(const Key('pharmacy-continue')));
    await tester.pumpAndSettle();
    expect(opens, 0);
    expect(find.byKey(const Key('pharmacy-continue')), findsNothing);
    expect(
      find.text('Your account session changed. Refresh to continue.'),
      findsOneWidget,
    );
  });
  testWidgets('unverified destinations preserve manual fallback', (
    tester,
  ) async {
    await pump(tester, FakePharmacy()..malicious = true);
    expect(find.byKey(const Key('pharmacy-continue')), findsNothing);
    expect(find.textContaining('Use the number on your label'), findsOneWidget);
  });
  testWidgets('renewal guides prescriber without pharmacy ordering button', (
    tester,
  ) async {
    await pump(tester, FakePharmacy());
    await tester.tap(find.byKey(const Key('pharmacy-purpose')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renewal').last);
    await tester.pumpAndSettle();
    expect(find.text('Ask your prescriber for a renewal.'), findsOneWidget);
    expect(find.byKey(const Key('pharmacy-continue')), findsNothing);
  });
  testWidgets('native fallback exposes only the reviewed official address', (
    tester,
  ) async {
    await pump(tester, FakePharmacy(), open: (_) async => false);
    await tester.ensureVisible(find.byKey(const Key('pharmacy-continue')));
    await tester.tap(find.byKey(const Key('pharmacy-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Copy website address'), findsOneWidget);
    expect(find.text('https://www.cvs.com/pharmacy/'), findsOneWidget);
  });
}
