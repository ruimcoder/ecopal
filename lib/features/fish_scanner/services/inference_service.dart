import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/detection_result.dart';
import 'frame_processor.dart';

/// Confidence threshold below which detections trigger the cloud fallback.
const double kConfidenceThreshold = 0.75;

/// The result of running inference on a single [ProcessedFrame].
class InferenceResult {
  const InferenceResult({
    required this.detections,
    required this.belowThreshold,
  });

  /// Detections whose confidence is ≥ [kConfidenceThreshold].
  final List<DetectionResult> detections;

  /// `true` when the best raw detection score was below [kConfidenceThreshold].
  ///
  /// When `true`, callers should trigger the cloud fallback.
  // TODO(#14): hook cloud fallback (iNaturalist) here when belowThreshold is true.
  final bool belowThreshold;
}

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

/// All candidate detections used in mock mode (cycling round-robin per call).
///
/// Index 3 (European Eel, confidence 0.65) is intentionally below threshold
/// so the cycling logic exercises the threshold path.
const List<_MockDetection> _kMockDetections = [
  _MockDetection(
    scientificName: 'Gadus morhua',
    rating: SeafoodWatchRating.goodAlternative,
    confidence: 0.82,
    boundingBox: Rect.fromLTWH(0.1, 0.1, 0.4, 0.5),
  ),
  _MockDetection(
    scientificName: 'Thunnus thynnus',
    rating: SeafoodWatchRating.avoid,
    confidence: 0.91,
    boundingBox: Rect.fromLTWH(0.05, 0.2, 0.45, 0.55),
  ),
  _MockDetection(
    scientificName: 'Salmo salar',
    rating: SeafoodWatchRating.bestChoice,
    confidence: 0.78,
    boundingBox: Rect.fromLTWH(0.15, 0.05, 0.35, 0.6),
  ),
  _MockDetection(
    scientificName: 'Anguilla anguilla',
    rating: SeafoodWatchRating.notRated,
    confidence: 0.65,
    boundingBox: Rect.fromLTWH(0.2, 0.15, 0.5, 0.45),
  ),
  _MockDetection(
    scientificName: 'Sardina pilchardus',
    rating: SeafoodWatchRating.bestChoice,
    confidence: 0.88,
    boundingBox: Rect.fromLTWH(0.08, 0.12, 0.42, 0.52),
  ),
];

class _MockDetection {
  const _MockDetection({
    required this.scientificName,
    required this.rating,
    required this.confidence,
    required this.boundingBox,
  });

  final String scientificName;
  final SeafoodWatchRating rating;
  final double confidence;
  final Rect boundingBox;
}

// ---------------------------------------------------------------------------
// Isolate payload types (must be sendable across isolate boundaries)
// ---------------------------------------------------------------------------

/// Input message sent to the inference isolate.
class _InferenceInput {
  const _InferenceInput({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Raw detection data returned from the inference isolate.
///
/// Uses plain primitives so it is safe to send across isolate ports.
class _RawDetection {
  const _RawDetection({
    required this.scientificName,
    required this.confidence,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String scientificName;
  final double confidence;
  final double left;
  final double top;
  final double width;
  final double height;
}

// ---------------------------------------------------------------------------
// Top-level isolate entry point (must NOT capture closures from outer scope)
// ---------------------------------------------------------------------------

/// Runs TFLite inference inside a Dart isolate.
///
/// Loaded from `assets/models/fish_classifier.tflite`. Returns a list of
/// [_RawDetection] records sorted by confidence descending.
Future<List<_RawDetection>> _runTfliteInference(
  _InferenceInput input,
) async {
  // TODO(#13): load fish_classifier.tflite with tflite_flutter and run real
  // inference here. Delegate chain: GPU → NNAPI → CPU (see ADR-002).
  //
  // Example skeleton (not yet active):
  //   final interpreter = await Interpreter.fromAsset(
  //     'models/fish_classifier.tflite',
  //     options: InterpreterOptions()..addDelegate(GpuDelegateV2()),
  //   );
  //   interpreter.run(inputTensor, outputTensor);
  throw UnimplementedError(
    '_runTfliteInference is a stub — enable useMockData or await Issue #13.',
  );
}

// ---------------------------------------------------------------------------
// InferenceService
// ---------------------------------------------------------------------------

/// Runs fish-species detection on a [ProcessedFrame] and returns
/// [InferenceResult] containing filtered [DetectionResult]s.
///
/// **Mock mode** (`useMockData = true`, the default): returns hardcoded
/// plausible detections cycling through a fixed set of 5 species. No model
/// file or GPU delegate is required. Use this during UI development while
/// Issue #13 (model training) is in progress.
///
/// **Real mode** (`useMockData = false`): loads
/// `assets/models/fish_classifier.tflite` and runs inference in a Dart
/// [Isolate] via [Isolate.run]. Requires the model asset to be present and
/// `tflite_flutter` native binaries to be linked.
///
/// Lifecycle:
/// ```dart
/// final svc = InferenceService();
/// await svc.init();
/// final result = await svc.infer(frame);
/// svc.dispose();
/// ```
class InferenceService {
  InferenceService({bool useMockData = true}) : _useMockData = useMockData;

  final bool _useMockData;
  bool _isInitialised = false;

  /// Round-robin counter for cycling mock detections.
  int _mockIndex = 0;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Initialises the service.
  ///
  /// Idempotent — safe to call multiple times (LP-001).
  Future<void> init() async {
    if (_isInitialised) return;
    // In real mode (Issue #13) this is where the TFLite interpreter would be
    // pre-warmed and the model asset loaded into memory.
    _isInitialised = true;
  }

  /// Releases all resources held by the service.
  ///
  /// Safe to call after [init] or before it.
  void dispose() {
    // In real mode (Issue #13) this is where the TFLite interpreter would be
    // closed and any GPU delegates released.
    _isInitialised = false;
  }

  // ---------------------------------------------------------------------------
  // Inference
  // ---------------------------------------------------------------------------

  /// Runs inference on [frame] and returns an [InferenceResult].
  ///
  /// Detections with confidence < [kConfidenceThreshold] are filtered out.
  /// When *all* raw detections fall below the threshold, [InferenceResult.belowThreshold]
  /// is `true` and the caller should invoke the cloud fallback.
  ///
  /// Throws [StateError] if [init] has not been called.
  Future<InferenceResult> infer(ProcessedFrame frame) async {
    if (!_isInitialised) {
      throw StateError('InferenceService.init() must be called before infer()');
    }

    final rawDetections = _useMockData
        ? _getMockDetections()
        : await Isolate.run(
            () => _runTfliteInference(
              _InferenceInput(
                bytes: frame.bytes,
                width: frame.width,
                height: frame.height,
              ),
            ),
          );

    return _buildResult(rawDetections);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Returns the next mock detection batch (single species, cycling).
  List<_RawDetection> _getMockDetections() {
    final mock = _kMockDetections[_mockIndex % _kMockDetections.length];
    _mockIndex++;
    return [
      _RawDetection(
        scientificName: mock.scientificName,
        confidence: mock.confidence,
        left: mock.boundingBox.left,
        top: mock.boundingBox.top,
        width: mock.boundingBox.width,
        height: mock.boundingBox.height,
      ),
    ];
  }

  /// Filters raw detections by threshold and constructs [InferenceResult].
  InferenceResult _buildResult(List<_RawDetection> raw) {
    if (raw.isEmpty) {
      return const InferenceResult(detections: [], belowThreshold: true);
    }

    final bestConfidence = raw
        .map((d) => d.confidence)
        .reduce((a, b) => a > b ? a : b);
    final belowThreshold = bestConfidence < kConfidenceThreshold;

    if (belowThreshold) {
      // TODO(#14): trigger iNaturalist cloud fallback here.
      debugPrint(
        'InferenceService: best confidence $bestConfidence < '
        '$kConfidenceThreshold — cloud fallback required.',
      );
      return const InferenceResult(detections: [], belowThreshold: true);
    }

    final detections = raw
        .where((d) => d.confidence >= kConfidenceThreshold)
        .map(
          (d) => DetectionResult(
            scientificName: d.scientificName,
            confidence: d.confidence,
            boundingBox: Rect.fromLTWH(d.left, d.top, d.width, d.height),
          ),
        )
        .toList();

    return InferenceResult(detections: detections, belowThreshold: false);
  }
}
