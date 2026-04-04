import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ecopal/features/fish_scanner/services/consent_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConsentService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('hasCloudFallbackConsent returns false initially', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = ConsentService(prefs);

      expect(await service.hasCloudFallbackConsent(), isFalse);
    });

    test('setCloudFallbackConsent(true) persists consent', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = ConsentService(prefs);

      await service.setCloudFallbackConsent(granted: true);

      expect(await service.hasCloudFallbackConsent(), isTrue);
    });

    test('setCloudFallbackConsent(false) persists denial', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = ConsentService(prefs);

      // Grant first, then revoke.
      await service.setCloudFallbackConsent(granted: true);
      await service.setCloudFallbackConsent(granted: false);

      expect(await service.hasCloudFallbackConsent(), isFalse);
    });

    testWidgets(
      'requestConsentIfNeeded returns true without dialog when already granted',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'cloud_fallback_consent_granted': true,
        });

        final prefs = await SharedPreferences.getInstance();
        final service = ConsentService(prefs);

        late bool result;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () async {
                    result = await service.requestConsentIfNeeded(context);
                  },
                  child: const Text('Test'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Test'));
        await tester.pump();

        // No dialog should be shown.
        expect(find.byType(AlertDialog), findsNothing);
        expect(result, isTrue);
      },
    );
  });
}
