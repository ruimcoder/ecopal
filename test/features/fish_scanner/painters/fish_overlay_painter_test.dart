import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecopal/features/fish_scanner/models/detection_result.dart';
import 'package:ecopal/features/fish_scanner/painters/fish_overlay_painter.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DetectionResult _detection({
  String scientificName = 'Gadus morhua',
  double confidence = 0.82,
  Rect boundingBox = const Rect.fromLTWH(0.1, 0.1, 0.4, 0.5),
  SpeciesInfo? speciesInfo,
}) =>
    DetectionResult(
      scientificName: scientificName,
      confidence: confidence,
      boundingBox: boundingBox,
      speciesInfo: speciesInfo,
    );

SpeciesInfo _speciesInfo({
  SeafoodWatchRating rating = SeafoodWatchRating.bestChoice,
}) =>
    SpeciesInfo(
      scientificName: 'Gadus morhua',
      rating: rating,
      commonNames: const {'en': 'Atlantic Cod'},
    );

/// Creates a [Canvas] backed by [PictureRecorder] for direct painter calls.
Canvas _makeCanvas() => Canvas(ui.PictureRecorder());

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FishOverlayPainter.shouldRepaint', () {
    test('returns false for the same detections list instance', () {
      final detections = [_detection()];
      final a = FishOverlayPainter(
        detections: detections,
        previewSize: const Size(640, 480),
      );
      final b = FishOverlayPainter(
        detections: detections,
        previewSize: const Size(640, 480),
      );

      expect(a.shouldRepaint(b), isFalse);
    });

    test('returns true when detections list is a new instance', () {
      final a = FishOverlayPainter(
        detections: [_detection()],
        previewSize: const Size(640, 480),
      );
      final b = FishOverlayPainter(
        detections: [_detection()], // different list object
        previewSize: const Size(640, 480),
      );

      expect(a.shouldRepaint(b), isTrue);
    });

    test('returns true when detections changes from empty to non-empty', () {
      const a = FishOverlayPainter(
        detections: [],
        previewSize: Size(640, 480),
      );
      final b = FishOverlayPainter(
        detections: [_detection()],
        previewSize: const Size(640, 480),
      );

      expect(a.shouldRepaint(b), isTrue);
    });

    test('returns false for the same empty list instance', () {
      const empty = <DetectionResult>[];
      const a = FishOverlayPainter(
        detections: empty,
        previewSize: Size(640, 480),
      );
      const b = FishOverlayPainter(
        detections: empty,
        previewSize: Size(640, 480),
      );

      expect(a.shouldRepaint(b), isFalse);
    });
  });

  group('FishOverlayPainter.paint — no-throw guarantees', () {
    test('does not throw for empty detections', () {
      const painter = FishOverlayPainter(
        detections: [],
        previewSize: Size(640, 480),
      );

      expect(
        () => painter.paint(_makeCanvas(), const Size(320, 240)),
        returnsNormally,
      );
    });

    test('does not throw for a detection without speciesInfo', () {
      final painter = FishOverlayPainter(
        detections: [_detection()],
        previewSize: const Size(640, 480),
      );

      expect(
        () => painter.paint(_makeCanvas(), const Size(320, 240)),
        returnsNormally,
      );
    });

    test('does not throw for a detection with speciesInfo', () {
      final painter = FishOverlayPainter(
        detections: [
          _detection(
            speciesInfo: _speciesInfo(rating: SeafoodWatchRating.avoid),
          ),
        ],
        previewSize: const Size(640, 480),
      );

      expect(
        () => painter.paint(_makeCanvas(), const Size(320, 240)),
        returnsNormally,
      );
    });

    test('does not throw for multiple detections', () {
      final painter = FishOverlayPainter(
        detections: [
          _detection(scientificName: 'Gadus morhua'),
          _detection(
            scientificName: 'Thunnus thynnus',
            boundingBox: const Rect.fromLTWH(0.2, 0.2, 0.3, 0.3),
          ),
          _detection(
            scientificName: 'Salmo salar',
            boundingBox: const Rect.fromLTWH(0.5, 0.5, 0.2, 0.2),
          ),
        ],
        previewSize: const Size(640, 480),
      );

      expect(
        () => painter.paint(_makeCanvas(), const Size(320, 240)),
        returnsNormally,
      );
    });

    test('handles bounding box that fills the entire canvas without throwing',
        () {
      final painter = FishOverlayPainter(
        detections: [
          _detection(
            boundingBox: const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0),
          ),
        ],
        previewSize: const Size(640, 480),
      );

      expect(
        () => painter.paint(_makeCanvas(), const Size(320, 240)),
        returnsNormally,
      );
    });
  });

  // Widget-based tests for rendered output.
  group('FishOverlayPainter — widget rendering', () {
    testWidgets('CustomPaint with FishOverlayPainter renders in a widget tree',
        (tester) async {
      final detections = [
        _detection(
          speciesInfo: _speciesInfo(rating: SeafoodWatchRating.bestChoice),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              painter: FishOverlayPainter(
                detections: detections,
                previewSize: const Size(640, 480),
              ),
              child: const SizedBox(width: 320, height: 240),
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is FishOverlayPainter,
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'FishOverlayPainter with empty detections renders without error',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              painter: FishOverlayPainter(
                detections: [],
                previewSize: Size(640, 480),
              ),
              child: SizedBox(width: 320, height: 240),
            ),
          ),
        ),
      );

      // No exceptions — widget tree is stable.
      expect(tester.takeException(), isNull);
    });
  });
}
