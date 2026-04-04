import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ecopal/features/fish_scanner/data/species_cache_db.dart';
import 'package:ecopal/features/fish_scanner/models/detection_result.dart';
import 'package:ecopal/features/fish_scanner/services/cloud_fallback_service.dart';
import 'package:ecopal/features/fish_scanner/services/consent_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fake [ConsentService] that returns [grantResult] immediately without
/// showing a dialog or touching SharedPreferences.
class _FakeConsentService extends ConsentService {
  _FakeConsentService({
    required this.grantResult,
    required SharedPreferences prefs,
  }) : super(prefs);

  final bool grantResult;

  @override
  Future<bool> requestConsentIfNeeded(BuildContext context) async => grantResult;
}

/// Minimal iNaturalist-shaped JSON response with a single top result.
String _inatResponse({required String scientificName, required double score}) {
  return jsonEncode({
    'total_results': 1,
    'results': [
      {
        'score': score,
        'taxon': {
          'name': scientificName,
          'iconic_taxon_name': 'Actinopterygii',
        },
      },
    ],
  });
}

/// A minimal non-empty byte payload (tiny JPEG header bytes).
final Uint8List _stubFrame = Uint8List.fromList([0xFF, 0xD8, 0xFF]);

/// Pumps a minimal widget tree and returns a real [BuildContext] for tests
/// whose [_FakeConsentService] ignores the context entirely.
Future<BuildContext> _buildContext(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  return tester.element(find.byType(SizedBox));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpeciesCacheDb.instance.init(dbPath: inMemoryDatabasePath);
  });

  tearDown(() async {
    await SpeciesCacheDb.instance.close();
  });

  group('CloudFallbackService', () {
    // -------------------------------------------------------------------------
    // Consent gate
    // -------------------------------------------------------------------------

    testWidgets('returns null immediately when consent is not granted',
        (tester) async {
      final ctx = await _buildContext(tester);
      final prefs = await SharedPreferences.getInstance();
      var sendCalled = false;
      final svc = CloudFallbackService(
        consentService: _FakeConsentService(grantResult: false, prefs: prefs),
        cacheDb: SpeciesCacheDb.instance,
        useMockData: false,
        sendFrameFn: (_) async {
          sendCalled = true;
          return '{}';
        },
      );

      final result = await tester.runAsync(() => svc.identify(_stubFrame, ctx));

      expect(result, isNull, reason: 'no frame should be sent without consent');
      expect(sendCalled, isFalse);
    });

    // -------------------------------------------------------------------------
    // Mock mode
    // -------------------------------------------------------------------------

    testWidgets('mock mode returns Thunnus obesus without calling sendFrameFn',
        (tester) async {
      final ctx = await _buildContext(tester);
      final prefs = await SharedPreferences.getInstance();
      var sendCalled = false;
      final svc = CloudFallbackService(
        consentService: _FakeConsentService(grantResult: true, prefs: prefs),
        cacheDb: SpeciesCacheDb.instance,
        useMockData: true,
        sendFrameFn: (_) async {
          sendCalled = true;
          return '{}';
        },
      );

      final result = await tester.runAsync(() => svc.identify(_stubFrame, ctx));

      expect(result, isNotNull);
      expect(result!.scientificName, equals('Thunnus obesus'));
      expect(result.boundingBox, equals(Rect.zero));
      expect(result.speciesInfo, isNotNull);
      expect(sendCalled, isFalse, reason: 'mock mode must never call sendFrameFn');
    });

    // -------------------------------------------------------------------------
    // HTTP failure
    // -------------------------------------------------------------------------

    testWidgets('returns null gracefully when sendFrameFn throws an exception',
        (tester) async {
      final ctx = await _buildContext(tester);
      final prefs = await SharedPreferences.getInstance();
      final svc = CloudFallbackService(
        consentService: _FakeConsentService(grantResult: true, prefs: prefs),
        cacheDb: SpeciesCacheDb.instance,
        useMockData: false,
        sendFrameFn: (_) async => throw Exception('Network failure'),
      );

      final result = await tester.runAsync(() => svc.identify(_stubFrame, ctx));

      expect(result, isNull);
    });

    // -------------------------------------------------------------------------
    // Timeout (LP-005)
    // -------------------------------------------------------------------------

    testWidgets('returns null gracefully on TimeoutException (LP-005)',
        (tester) async {
      final ctx = await _buildContext(tester);
      final prefs = await SharedPreferences.getInstance();
      final svc = CloudFallbackService(
        consentService: _FakeConsentService(grantResult: true, prefs: prefs),
        cacheDb: SpeciesCacheDb.instance,
        useMockData: false,
        sendFrameFn: (_) async => throw TimeoutException(
          'simulated 15s timeout',
          const Duration(seconds: 15),
        ),
      );

      final result = await tester.runAsync(() => svc.identify(_stubFrame, ctx));

      expect(result, isNull);
    });

    // -------------------------------------------------------------------------
    // Caching — entire body in runAsync so sqflite Futures complete in the
    // real event loop (not the testWidgets fake-async zone).
    // -------------------------------------------------------------------------

    testWidgets(
        'caches result in SpeciesCacheDb after successful identification',
        (tester) async {
      final ctx = await _buildContext(tester);

      await tester.runAsync(() async {
        const scientificName = 'Gadus morhua';
        const score = 0.92;

        final prefs = await SharedPreferences.getInstance();
        final svc = CloudFallbackService(
          consentService: _FakeConsentService(grantResult: true, prefs: prefs),
          cacheDb: SpeciesCacheDb.instance,
          useMockData: false,
          sendFrameFn: (_) async =>
              _inatResponse(scientificName: scientificName, score: score),
        );

        final result = await svc.identify(_stubFrame, ctx);

        expect(result, isNotNull);
        expect(result!.scientificName, equals(scientificName));
        expect(result.confidence, equals(score));
        expect(result.boundingBox, equals(Rect.zero));
        expect(result.speciesInfo!.rating, equals(SeafoodWatchRating.notRated));

        final cached =
            await SpeciesCacheDb.instance.lookup(scientificName, 'en');
        expect(cached, isNotNull, reason: 'result must be written to cache');
        expect(cached!.scientificName, equals(scientificName));
        expect(cached.rating, equals(SeafoodWatchRating.notRated));
      });
    });

    testWidgets('mock mode result is also cached in SpeciesCacheDb',
        (tester) async {
      final ctx = await _buildContext(tester);

      await tester.runAsync(() async {
        final prefs = await SharedPreferences.getInstance();
        final svc = CloudFallbackService(
          consentService: _FakeConsentService(grantResult: true, prefs: prefs),
          cacheDb: SpeciesCacheDb.instance,
          useMockData: true,
        );

        final result = await svc.identify(_stubFrame, ctx);

        expect(result, isNotNull);

        final cached =
            await SpeciesCacheDb.instance.lookup('Thunnus obesus', 'en');
        expect(cached, isNotNull, reason: 'mock result must also be cached');
      });
    });
  });
}