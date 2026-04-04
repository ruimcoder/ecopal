import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Pixel data extracted from a [CameraImage] for transfer across isolate boundaries.
class _FrameData {
  const _FrameData({
    required this.planes,
    required this.rowStrides,
    required this.width,
    required this.height,
    required this.timestamp,
  });

  final List<Uint8List> planes;
  final List<int> rowStrides;
  final int width;
  final int height;
  final DateTime timestamp;
}

/// RGBA pixel data produced after YUV420→RGBA conversion, ready for ML inference.
class ProcessedFrame {
  const ProcessedFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
    required this.timestamp,
  });

  /// Raw pixel bytes in [format] channel order.
  final Uint8List bytes;

  final int width;
  final int height;

  /// Pixel channel order, e.g. `'RGBA'`.
  final String format;

  /// Wall-clock time when the source camera frame was sampled.
  final DateTime timestamp;
}

/// Top-level YUV420→RGBA conversion function.
///
/// Must be top-level (not a closure) so [compute] can execute it in a Dart
/// isolate without capturing any mutable state.
ProcessedFrame _convertYuvToRgba(_FrameData data) {
  final w = data.width;
  final h = data.height;
  final yPlane = data.planes[0];
  final uPlane = data.planes[1];
  final vPlane = data.planes[2];
  final yStride = data.rowStrides[0];
  final uvStride =
      data.rowStrides.length > 1 ? data.rowStrides[1] : (w + 1) ~/ 2;

  final rgba = Uint8List(w * h * 4);
  var outIdx = 0;

  for (var row = 0; row < h; row++) {
    for (var col = 0; col < w; col++) {
      final yVal = yPlane[row * yStride + col] & 0xFF;
      final uvRow = row ~/ 2;
      final uvCol = col ~/ 2;
      final uvIdx = uvRow * uvStride + uvCol;

      final uVal = (uvIdx < uPlane.length ? uPlane[uvIdx] : 128) & 0xFF;
      final vVal = (uvIdx < vPlane.length ? vPlane[uvIdx] : 128) & 0xFF;

      rgba[outIdx++] =
          (yVal + 1.402 * (vVal - 128)).round().clamp(0, 255);
      rgba[outIdx++] =
          (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128))
              .round()
              .clamp(0, 255);
      rgba[outIdx++] =
          (yVal + 1.772 * (uVal - 128)).round().clamp(0, 255);
      rgba[outIdx++] = 255;
    }
  }

  // Use the image package to normalise the buffer for cross-platform
  // compatibility.
  final image = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );

  return ProcessedFrame(
    bytes: image.getBytes(order: img.ChannelOrder.rgba),
    width: image.width,
    height: image.height,
    format: 'RGBA',
    timestamp: data.timestamp,
  );
}

/// Conversion function signature.
///
/// Exposed so tests can inject a lightweight stub converter instead of the
/// default [compute]-based implementation.
typedef FrameConverterFn = Future<ProcessedFrame> Function(
  CameraImage image,
  DateTime timestamp,
);

/// Returns the current wall-clock time.
typedef ClockFn = DateTime Function();

/// Samples a [CameraImage] stream at up to 5 fps, converts frames from
/// YUV420→RGBA in a background [Isolate] via [compute], and emits
/// [ProcessedFrame]s on [frames].
///
/// Usage:
/// ```dart
/// final processor = FrameProcessor();
/// processor.start(cameraService.imageStream);
/// processor.frames.listen((frame) { /* use frame */ });
/// ```
class FrameProcessor {
  FrameProcessor({FrameConverterFn? converter, ClockFn? clock})
      : _converter = converter ?? _defaultConvert,
        _clock = clock ?? DateTime.now;

  static const int _maxFps = 5;
  static const Duration _minFrameInterval =
      Duration(milliseconds: 1000 ~/ _maxFps);

  final FrameConverterFn _converter;
  final ClockFn _clock;

  final StreamController<ProcessedFrame> _controller =
      StreamController<ProcessedFrame>.broadcast();

  StreamSubscription<CameraImage>? _subscription;
  DateTime? _lastFrameTime;

  /// Stream of [ProcessedFrame]s throttled to at most [_maxFps] frames/second.
  Stream<ProcessedFrame> get frames => _controller.stream;

  /// Begins sampling [cameraStream] at up to [_maxFps] fps.
  void start(Stream<CameraImage> cameraStream) {
    _subscription?.cancel();
    _lastFrameTime = null;
    _subscription = cameraStream.listen(_onFrame);
  }

  /// Cancels the subscription to the camera stream.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Stops sampling and closes the [frames] stream.
  Future<void> dispose() async {
    stop();
    await _controller.close();
  }

  Future<void> _onFrame(CameraImage image) async {
    final now = _clock();
    final last = _lastFrameTime;
    if (last != null && now.difference(last) < _minFrameInterval) return;
    _lastFrameTime = now;

    if (_controller.isClosed) return;

    final processed = await _converter(image, now);
    // TODO(#12): pass processed frame to ML inference pipeline here.
    if (!_controller.isClosed) {
      _controller.add(processed);
    }
  }

  static Future<ProcessedFrame> _defaultConvert(
    CameraImage image,
    DateTime timestamp,
  ) {
    final data = _FrameData(
      planes: image.planes
          .map((plane) => Uint8List.fromList(plane.bytes))
          .toList(),
      rowStrides: image.planes.map((plane) => plane.bytesPerRow).toList(),
      width: image.width,
      height: image.height,
      timestamp: timestamp,
    );
    return compute(_convertYuvToRgba, data);
  }
}
