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

class _PermissionDeniedCameraService extends CameraService {
  _PermissionDeniedCameraService()
      : super(
          cameras: const [],
          permissionRequester: () async => PermissionStatus.denied,
        );
}

class _ReadyCameraService extends CameraService {
  _ReadyCameraService()
      : _fakeController = _FakeCameraController(),
        super(
          cameras: const [],
          permissionRequester: () async => PermissionStatus.granted,
        );

  final _FakeCameraController _fakeController;

  @override
  Future<void> initialize() async {}

  @override
  CameraController? get controller => _fakeController;

  @override
  Stream<CameraImage> get imageStream => const Stream.empty();

  @override
  Future<void> startImageStream() async {}

  @override
  Future<void> stopImageStream() async {}

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> dispose() async {
    errorMessage.dispose();
  }
}

class _FakeCameraController extends CameraController {
  static const _fakeDesc = CameraDescription(
    name: 'fake',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 0,
  );

  _FakeCameraController() : super(_fakeDesc, ResolutionPreset.low);

  @override
  CameraValue get value =>
      const CameraValue.uninitialized(_fakeDesc).copyWith(
        isInitialized: true,
        previewSize: const Size(640, 480),
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

const _stubDetection = DetectionResult(
  scientificName: 'Gadus morhua',
  confidence: 0.9,
  boundingBox: Rect.fromLTWH(0.1, 0.1, 0.4, 0.5),
  speciesInfo: SpeciesInfo(
    scientificName: 'Gadus morhua',
    rating: SeafoodWatchRating.goodAlternative,
    commonNames: {'en': 'Atlantic Cod'},
  ),
);

const _aboveThresholdResult = InferenceResult(
  detections: [_stubDetection],
  belowThreshold: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FishScannerScreen builds without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FishScannerScreen(
          cameraService: _PermissionDeniedCameraService(),
        ),
      ),
    );
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
    await tester.pumpAndSettle();
    expect(find.text('Camera permission denied'), findsWidgets);
    expect(find.text('Open Settings'), findsOneWidget);
  });

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
      expect(find.byType(FishScannerScreen), findsOneWidget);
    },
  );

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
      // Settle the async _initPipeline future and FutureBuilder rebuild.
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

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
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      final customPaint = tester.widget<CustomPaint>(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is FishOverlayPainter,
        ),
      );
      final painter = customPaint.painter! as FishOverlayPainter;
      expect(painter.detections, isEmpty);
    },
  );
}