import 'dart:io';
import 'package:farda/consumer_v2/screens/refills/refills_handoff_screen.dart';
import 'package:farda/features/consumer/data/pharmacy_handoff.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../consumer_v2/refills/refill_agent_test.dart' show FakeAgent;
import '../consumer_v2/refills/pharmacy_handoff_test.dart' show FakePharmacy;

class VisualPharmacy extends FakeAgent implements PharmacyHandoffRepository {
  final pharmacy = FakePharmacy();
  @override
  Future<Future<bool> Function()> capturePharmacySession() =>
      pharmacy.capturePharmacySession();
  @override
  Future<List<PharmacyDestination>> loadPharmacyDirectory() =>
      pharmacy.loadPharmacyDirectory();
  @override
  Future<PharmacyHandoff> preparePharmacyHandoff(
    String id, {
    required String pharmacyId,
    required String purpose,
  }) => pharmacy.preparePharmacyHandoff(
    id,
    pharmacyId: pharmacyId,
    purpose: purpose,
  );
}

void main() {
  for (final narrow in [false, true]) {
    testWidgets('${narrow ? 320 : 390} pharmacy handoff readable', (
      tester,
    ) async {
      final fonts = FontLoader('Outfit');
      for (final weight in ['Light', 'Regular', 'Medium', 'SemiBold', 'Bold']) {
        fonts.addFont(rootBundle.load('assets/fonts/Outfit-$weight.ttf'));
      }
      await fonts.load();
      final bytes =
          File(
            '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytesSync();
      await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      tester.view.physicalSize = Size(narrow ? 320 : 390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Outfit'),
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(narrow ? 1.3 : 1)),
                child: child!,
              ),
          home: RefillsHandoffScreen(
            medicationName: 'Example medication',
            rxLabel: '',
            rxNumber: '123456',
            pharmacy: 'CVS',
            actionLabel: 'Save my refill plan',
            onSavePlan: () async => null,
            prescriptionId: 'p1',
            agentRepository: VisualPharmacy(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('UPDATE_VISUALS')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/${narrow ? '320-large-text' : '390'}-pharmacy-handoff.png',
          ),
        );
      }
    });
  }
}
