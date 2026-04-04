import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:ecopal/features/fish_scanner/models/detection_result.dart';
import 'package:ecopal/features/fish_scanner/painters/fish_overlay_painter.dart';
import 'package:ecopal/features/fish_scanner/screens/fish_scanner_screen.dart';
import 'package:ecopal/features/fish_scanner/services/camera_service.dart';
import 'package:ecopal/features/fish_scanner/services/frame_processor.dart';
import 'package:ecopal/features/fish_scanner/services/inference_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

// ---------------------------------------------------------------------------
// Camera fakes
// ---------------------------------------------------------------------------

/// A [CameraService] that immediately reports a permission denied error,
/// so the scanner screen can be tested without real hardware.
class _PermissionDeniedCameraService extends CameraService {
  _PermissionDeniedCameraService()
      : super(
          cameras: const [],
          permissionRequester: () async => PermissionStatus.denied,
        );
}

/// A [CameraService] that simulates a successfully initialised camera backed
/// by a [_FakeCameraController], allowing the overlay stack to be rendered.
class _ReadyCameraService extends CameraService {
  _ReadyCameraService()
      : _fakeController = _FakeCameraController(),
        super(
          cameras: const [],
          permissionRequester: () async => PermissionStatus.granted,
        );

  final _FakeCameraController _fakeController;

  @override
  Future<void> initialize() async {
    // Skip real camera initialisation — just mark as ready.
  }

  @override
  CameraController? get controller => _fakeController;

  @override
  Stream<CameraImage> get imageStream => const Stream.empty();

  @override
  void startImageStream() {}

  @override
  void stopImageStream() {}

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> dispose() async {
    errorMessage.dispose();
  }
}

/// Minimal [CameraController] that reports itself as initialised without
/// accessing any native platform APIs.
class _FakeCameraController extends CameraController {
  static const _fakeDesc = CameraDescription(
    name: 'fake',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 0,
  );

  _FakeCameraController() : super(_fakeDesc, ResolutionPreset.low);

  @override
  CameraValue get value => const CameraValue.uninitialized(_fakeDesc).copyWith(
        isInitialized: true,
      );

  @override
  Future<void> initialize() async {}

  @override
  Widget buildPreview() => const SizedBox.expand(key: Key('camera-preview'));

  @override
  Future<void> startImageStream(onAvailable) async {}

  @override
  Future<void> stopImageStream() async {}

  @override
  Future<void> dispose() async {
    await super.dispose();
  }
}

// ---------------------------------------------------------------------------
// InferenceService fake
// ---------------------------------------------------------------------------

/// Synchronous [InferenceService] stub that returns a preset result.
class _StubInferenceService extends InferenceService {
  _StubInferenceService({required this.result}) : super(useMockData: false);

  final InferenceResult result;

  @override
  Future<void> init() async {}

  @override
  Future<InferenceResult> infer(ProcessedFrame frame) async => result;

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

final _stubDetection = DetectionResult(
  scientificName: 'Gadus morhua',
  confidence: 0.9,
  boundingBox: const Rect.fromLTWH(0.1, 0.1, 0.4, 0.5),
  speciesInfo: const SpeciesInfo(
    scientificName: 'Gadus morhua',
    rating: SeafoodWatchRating.goodAlternative,
    commonNames: {'en': 'Atlantic Cod'},
  ),
);

final _aboveThresholdResult = InferenceResult(
  detections: [_stubDetection],
  belowThreshold: false,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Existing baseline tests ─────────────────────────────────────────────

  testWidgets('FishScannerScreen builds without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FishScannerScreen(
          cameraService: _PermissionDeniedCameraService(),
        ),
      ),
    );

    // Initial frame — FutureBuilder has not resolved yet.
    expect(find.byType(FishScannerScreen), findsOneWidget);
  });

  testWidgets('FishScannerScreen shows loading indicator initially',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FishScannerScreen(
          cameraService: _PermissionDeniedCameraService(),
        ),
      ),
    );

    // Before the future completes the loading spinner must be visible.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
      'FishScannerScreen shows permission denied error after init completes',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FishScannerScreen(
          cameraService: _PermissionDeniedCameraService(),
        ),
      ),
    );

    // Settle all async work (initialize + FutureBuilder).
    await tester.pumpAndSettle();

    expect(find.text('Camera permission denied'), findsWidgets);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  // ── inferenceService injection ──────────────────────────────────────────

  testWidgets(
    'FishScannerScreen accepts injected InferenceService without error',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FishScannerScreen(
            cameraService: _PermissionDeniedCameraService(),
            inferenceService: _StubInferenceService(
              result: _aboveThresholdResult,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Screen still renders the error view (no camera in test), but the
      // injected InferenceService must not cause any exception.
      expect(find.byType(FishScannerScreen), findsOneWidget);
    },
  );

  // ── FishOverlayPainter wiring ───────────────────────────────────────────

  testWidgets(
    'FishScannerScreen contains a CustomPaint with FishOverlayPainter '
    'when the camera is ready',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FishScannerScreen(
            cameraService: _ReadyCameraService(),
            inferenceService: _StubInferenceService(
              result: _aboveThresholdResult,
            ),
          ),
        ),
      );

      // Let camera init settle.
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is FishOverlayPainter,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'FishOverlayPainter starts with empty detections before first frame',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FishScannerScreen(
            cameraService: _ReadyCameraService(),
            inferenceService: _StubInferenceService(
              result: _aboveThresholdResult,
            ),
          ),
        ),
      );
      await tester.pump();

      final customPaint = tester.widget<CustomPaint>(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is FishOverlayPainter,
        ),
      );
      final painter = customPaint.painter! as FishOverlayPainter;

      // No frames have been pushed — detections list must be empty.
      expect(painter.detections, isEmpty);
    },
  );
}
