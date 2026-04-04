import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Manages the device camera lifecycle for the Fish Scanner feature.
///
/// Callers must call [initialize] before accessing [controller] or
/// [imageStream], and [dispose] when the camera is no longer needed.
class CameraService {
  CameraController? _controller;
  final _imageStreamController = StreamController<CameraImage>.broadcast();
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);

  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;

  CameraController? get controller => _controller;

  /// Emits raw [CameraImage] frames from the active camera.
  ///
  /// TODO(#XX): move frame processing into a separate Isolate to keep UI jank-free.
  Stream<CameraImage> get imageStream => _imageStreamController.stream;

  /// Requests camera permission and initialises the [CameraController].
  ///
  /// Throws [CameraException] if the camera cannot be opened.
  Future<void> initialize() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        // TODO(#27): AppLocalizations — camera permission denied message
        errorMessage.value = 'Camera permission denied';
        return;
      }

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        // TODO(#27): AppLocalizations — no cameras available message
        errorMessage.value = 'No cameras available on this device';
        return;
      }

      // Default to rear camera; fall back to first available.
      _cameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (_cameraIndex == -1) _cameraIndex = 0;

      await _createController(_cameras[_cameraIndex]);
    } on CameraException catch (e) {
      errorMessage.value = e.description;
    }
  }

  Future<void> _createController(CameraDescription description) async {
    final previous = _controller;
    if (previous != null) {
      await previous.stopImageStream().catchError((_) {});
      await previous.dispose();
    }

    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _controller = controller;

    await controller.initialize();
    await controller.startImageStream((image) {
      if (!_imageStreamController.isClosed) {
        _imageStreamController.add(image);
      }
    });
  }

  /// Switches between front and back cameras.
  Future<void> switchCamera() async {
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    try {
      await _createController(_cameras[_cameraIndex]);
      errorMessage.value = null;
    } on CameraException catch (e) {
      errorMessage.value = e.description;
    }
  }

  /// Stops the image stream without disposing the controller.
  Future<void> stopImageStream() async {
    try {
      await _controller?.stopImageStream();
    } on CameraException catch (e) {
      errorMessage.value = e.description;
    }
  }

  /// Resumes the image stream after [stopImageStream].
  Future<void> startImageStream() async {
    try {
      await _controller?.startImageStream((image) {
        if (!_imageStreamController.isClosed) {
          _imageStreamController.add(image);
        }
      });
    } on CameraException catch (e) {
      errorMessage.value = e.description;
    }
  }

  /// Releases all camera resources.
  Future<void> dispose() async {
    await _imageStreamController.close();
    try {
      await _controller?.stopImageStream();
    } on CameraException catch (_) {}
    await _controller?.dispose();
    _controller = null;
    errorMessage.dispose();
  }
}
