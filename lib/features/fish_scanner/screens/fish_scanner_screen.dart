import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/detection_result.dart';
import '../painters/fish_overlay_painter.dart';
import '../services/camera_service.dart';
import '../services/frame_processor.dart';
import '../services/inference_service.dart';
import '../widgets/species_info_card.dart';

/// Main Fish Scanner screen.
///
/// Displays a full-bleed [CameraPreview] with a transparent overlay [Stack]
/// for bounding boxes (drawn by [FishOverlayPainter]) and a bottom info panel
/// showing the detected species name, common name, and rating badge.
///
/// [inferenceService] is constructor-injected so tests can supply a mock.
/// Defaults to a real [InferenceService] (mock-data mode until Issue #13).
///
/// Manages camera lifecycle through [WidgetsBindingObserver]: pauses the image
/// stream when the app is backgrounded and resumes it on foreground.
class FishScannerScreen extends StatefulWidget {
  const FishScannerScreen({
    super.key,
    CameraService? cameraService,
    InferenceService? inferenceService,
  })  : _cameraService = cameraService,
        _inferenceService = inferenceService;

  final CameraService? _cameraService;
  final InferenceService? _inferenceService;

  @override
  State<FishScannerScreen> createState() => _FishScannerScreenState();
}

class _FishScannerScreenState extends State<FishScannerScreen>
    with WidgetsBindingObserver {
  late final CameraService _cameraService;
  late final FrameProcessor _frameProcessor;
  late final InferenceService _inferenceService;
  late final Future<void> _initFuture;

  StreamSubscription<ProcessedFrame>? _frameSubscription;

  /// Latest inference result from the ML pipeline.
  InferenceResult? _inferenceResult;

  // TODO(#27): replace hardcoded strings with AppLocalizations
  static const SpeciesInfo _stubSpecies = SpeciesInfo(
    scientificName: 'Thunnus thynnus',
    rating: SeafoodWatchRating.avoid,
    commonNames: {'en': 'Atlantic Bluefin Tuna'},
  );

  @override
  void initState() {
    super.initState();
    _cameraService = widget._cameraService ?? CameraService();
    _frameProcessor = FrameProcessor();
    _inferenceService = widget._inferenceService ?? InferenceService();
    WidgetsBinding.instance.addObserver(this);
    _initFuture = _initPipeline();
  }

  /// Initialises camera, inference service, and wires the frame pipeline.
  ///
  /// [InferenceService.init] is idempotent (LP-001) — safe to call here.
  Future<void> _initPipeline() async {
    await _inferenceService.init();
    await _cameraService.initialize();
    if (_cameraService.errorMessage.value == null) {
      _frameProcessor.start(_cameraService.imageStream);
      _frameSubscription = _frameProcessor.frames.listen(_onFrame);
    }
    _cameraService.errorMessage.addListener(_onCameraError);
  }

  /// Processes each [ProcessedFrame] through inference and refreshes the UI.
  Future<void> _onFrame(ProcessedFrame frame) async {
    try {
      final result = await _inferenceService.infer(frame);
      if (mounted) setState(() => _inferenceResult = result);
    } on Exception catch (e) {
      debugPrint('FishScannerScreen: inference error — $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _frameSubscription?.pause();
        _frameProcessor.stop();
        _cameraService.stopImageStream();
      case AppLifecycleState.resumed:
        _cameraService.startImageStream();
        if (_cameraService.controller?.value.isInitialized ?? false) {
          _frameProcessor.start(_cameraService.imageStream);
          _frameSubscription?.resume();
        }
      default:
        break;
    }
  }

  void _onCameraError() {
    final msg = _cameraService.errorMessage.value;
    if (msg == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // TODO(#27): AppLocalizations — camera error snackbar
        content: Text(msg),
        action: const SnackBarAction(
          // TODO(#27): AppLocalizations — open settings label
          label: 'Settings',
          onPressed: openAppSettings,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.errorMessage.removeListener(_onCameraError);
    _frameSubscription?.cancel();
    _frameProcessor.dispose();
    _inferenceService.dispose();
    _cameraService.dispose();
    super.dispose();
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          // TODO(#27): AppLocalizations.of(context)!.appTitle
          'ecopal',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            // TODO(#27): AppLocalizations — switch camera tooltip
            tooltip: 'Switch camera',
            icon: const Icon(Icons.flip_camera_android, color: Colors.white),
            onPressed: () async {
              await _cameraService.switchCamera();
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            // TODO(#27): AppLocalizations — settings tooltip
            tooltip: 'Settings',
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              // Settings screen — future issue
            },
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _LoadingView(colorScheme: colorScheme);
          }

          final error = _cameraService.errorMessage.value;
          if (error != null) {
            return _ErrorView(
              error: error,
              colorScheme: colorScheme,
              onRetry: _onRetry,
            );
          }

          final controller = _cameraService.controller;
          if (controller == null || !controller.value.isInitialized) {
            return _LoadingView(colorScheme: colorScheme);
          }

          return _ScannerView(
            controller: controller,
            detections: _inferenceResult?.detections ?? const [],
            stubSpecies: _stubSpecies,
            errorMessage: _cameraService.errorMessage,
            colorScheme: colorScheme,
          );
        },
      ),
    );
  }

  Future<void> _onRetry() async {
    setState(() {});
    await _cameraService.initialize();
    if (_cameraService.errorMessage.value == null) {
      _frameProcessor.start(_cameraService.imageStream);
      _frameSubscription ??= _frameProcessor.frames.listen(_onFrame);
    }
  }
}

// ── Private sub-widgets ──────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(color: colorScheme.primary),
    );
  }
}

/// Shown when camera initialisation fails (permission denied or hardware error).
class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.error,
    required this.colorScheme,
    required this.onRetry,
  });

  final String error;
  final ColorScheme colorScheme;
  final VoidCallback onRetry;

  static const _permissionDeniedSubstring = 'permission';

  @override
  Widget build(BuildContext context) {
    final isPermissionError =
        error.toLowerCase().contains(_permissionDeniedSubstring);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPermissionError ? Icons.no_photography : Icons.error_outline,
              size: 64,
              color: colorScheme.onSurface.withAlpha(128),
            ),
            const SizedBox(height: 16),
            Text(
              // TODO(#27): AppLocalizations — camera error heading
              isPermissionError ? 'Camera permission denied' : 'Camera unavailable',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withAlpha(179),
                  ),
            ),
            const SizedBox(height: 16),
            if (isPermissionError)
              FilledButton.icon(
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings),
                // TODO(#27): AppLocalizations — open settings button
                label: const Text('Open Settings'),
              )
            else
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                // TODO(#27): AppLocalizations — retry button
                label: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }
}

/// The camera preview + overlay stack shown when the camera is ready.
class _ScannerView extends StatelessWidget {
  const _ScannerView({
    required this.controller,
    required this.detections,
    required this.stubSpecies,
    required this.errorMessage,
    required this.colorScheme,
  });

  final CameraController controller;

  /// Live detections from the most recent inference run.
  final List<DetectionResult> detections;

  /// Fallback species shown in the info card when [detections] is empty.
  // TODO(#27): replace hardcoded strings with AppLocalizations
  final SpeciesInfo stubSpecies;

  final ValueNotifier<String?> errorMessage;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: errorMessage,
      builder: (context, _) {
        final liveError = errorMessage.value;
        if (liveError != null) {
          return Center(
            child: Text(
              liveError,
              style: TextStyle(color: colorScheme.error),
            ),
          );
        }

        // Resolve species: first live detection or stub fallback.
        final activeSpecies =
            detections.isNotEmpty ? detections.first.speciesInfo : null;
        final displaySpecies = activeSpecies ?? stubSpecies;

        // Camera preview dimensions for bounding-box scaling.
        final previewSize = controller.value.previewSize ?? Size.zero;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1 — full-bleed camera preview.
            CameraPreview(controller),

            // Layer 2 — bounding-box overlay painted by FishOverlayPainter.
            IgnorePointer(
              child: CustomPaint(
                painter: FishOverlayPainter(
                  detections: detections,
                  previewSize: previewSize,
                ),
              ),
            ),

            // Layer 3 — bottom info panel.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SpeciesInfoCard(speciesInfo: displaySpecies),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
