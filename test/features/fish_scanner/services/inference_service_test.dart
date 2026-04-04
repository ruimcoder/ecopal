import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ecopal/features/fish_scanner/services/frame_processor.dart';
import 'package:ecopal/features/fish_scanner/services/inference_service.dart';

/// Minimal [ProcessedFrame] suitable for unit tests (1×1 RGBA, no real pixels).
ProcessedFrame _stubFrame() => ProcessedFrame(
      bytes: Uint8List.fromList([0, 0, 0, 255]),
      width: 1,
      height: 1,
      format: 'RGBA',
      timestamp: DateTime(2025),
    );

void main() {
  group('InferenceService (mock mode)', () {
    late InferenceService svc;

    setUp(() {
      svc = InferenceService();
    });

    tearDown(() {
      svc.dispose();
    });

    // -------------------------------------------------------------------------
    // Lifecycle
    // -------------------------------------------------------------------------

    test('init() is idempotent — LP-001', () async {
      await svc.init();
      // Calling init() a second time must not throw or reset state.
      await expectLater(svc.init(), completes);
    });

    test('dispose() can be called safely after init()', () async {
      await svc.init();
      expect(() => svc.dispose(), returnsNormally);
    });

    test('dispose() can be called before init() without throwing', () {
      expect(() => svc.dispose(), returnsNormally);
    });

    test('infer() throws StateError when called before init()', () async {
      await expectLater(
        svc.infer(_stubFrame()),
        throwsA(isA<StateError>()),
      );
    });

    // -------------------------------------------------------------------------
    // Mock detections
    // -------------------------------------------------------------------------

    test('mock mode returns non-empty detections for above-threshold species',
        () async {
      await svc.init();

      // The first mock entry (Gadus morhua, 0.82) is above threshold.
      final result = await svc.infer(_stubFrame());

      expect(result.detections, isNotEmpty);
      expect(result.belowThreshold, isFalse);
    });

    test('mock detections have valid scientific names and confidence values',
        () async {
      await svc.init();
      final result = await svc.infer(_stubFrame());

      for (final d in result.detections) {
        expect(d.scientificName, isNotEmpty);
        expect(d.confidence, greaterThanOrEqualTo(kConfidenceThreshold));
        expect(d.confidence, lessThanOrEqualTo(1.0));
      }
    });

    test('mock detections have non-null, normalised bounding boxes', () async {
      await svc.init();
      final result = await svc.infer(_stubFrame());

      for (final d in result.detections) {
        final box = d.boundingBox;
        expect(box.left, greaterThanOrEqualTo(0.0));
        expect(box.top, greaterThanOrEqualTo(0.0));
        expect(box.width, greaterThan(0.0));
        expect(box.height, greaterThan(0.0));
        expect(box.right, lessThanOrEqualTo(1.0));
        expect(box.bottom, lessThanOrEqualTo(1.0));
      }
    });

    // -------------------------------------------------------------------------
    // Confidence threshold filtering
    // -------------------------------------------------------------------------

    test('detections below 0.75 confidence threshold are filtered out',
        () async {
      await svc.init();

      // Cycle through all 5 mock entries. The European Eel (index 3, confidence
      // 0.65) is below threshold — call infer() 4 times to reach it.
      InferenceResult? eelResult;
      for (var i = 0; i < 5; i++) {
        final r = await svc.infer(_stubFrame());
        if (r.belowThreshold) {
          eelResult = r;
          break;
        }
      }

      expect(
        eelResult,
        isNotNull,
        reason:
            'Expected at least one below-threshold result cycling through mocks',
      );
      expect(eelResult!.detections, isEmpty);
      expect(eelResult.belowThreshold, isTrue);
    });

    test('belowThreshold is true when best detection confidence < 0.75',
        () async {
      // Use a fresh service and cycle to the below-threshold mock entry.
      final fresh = InferenceService();
      await fresh.init();
      InferenceResult? belowResult;
      for (var i = 0; i < 5; i++) {
        final r = await fresh.infer(_stubFrame());
        if (r.belowThreshold) {
          belowResult = r;
          break;
        }
      }
      fresh.dispose();

      expect(belowResult, isNotNull);
      expect(belowResult!.belowThreshold, isTrue);
    });

    test('belowThreshold is false when best detection confidence >= 0.75',
        () async {
      await svc.init();
      // First mock entry (Gadus morhua, 0.82) is above threshold.
      final result = await svc.infer(_stubFrame());
      expect(result.belowThreshold, isFalse);
    });

    // -------------------------------------------------------------------------
    // Cycling behaviour
    // -------------------------------------------------------------------------

    test('successive calls cycle through distinct mock species', () async {
      await svc.init();
      final names = <String>[];
      for (var i = 0; i < 5; i++) {
        final r = await svc.infer(_stubFrame());
        // below-threshold results have no detections — record the species name
        // from belowThreshold logic indirectly via the cycling index.
        if (r.detections.isNotEmpty) {
          names.add(r.detections.first.scientificName);
        }
      }
      // Should have seen at least 2 distinct above-threshold species.
      expect(names.toSet().length, greaterThan(1));
    });

    // -------------------------------------------------------------------------
    // kConfidenceThreshold constant
    // -------------------------------------------------------------------------

    test('kConfidenceThreshold equals 0.75', () {
      expect(kConfidenceThreshold, equals(0.75));
    });
  });
}
