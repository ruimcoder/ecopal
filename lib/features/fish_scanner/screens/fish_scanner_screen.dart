import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/detection_result.dart';
import '../services/camera_service.dart';
import '../services/frame_processor.dart';
import '../widgets/species_info_card.dart';

/// Main Fish Scanner screen.
///
/// Displays a full-bleed [CameraPreview] with a transparent overlay [Stack]
/// for bounding boxes (painted in Issue #22) and a bottom info panel showing
/// the detected species name, common name, and rating badge.
///
/// Manages camera lifecycle through [WidgetsBindingObserver]: pauses the image
/// stream when the app is backgrounded and resumes it on foreground.
class FishScannerScreen extends StatefulWidget {
  const FishScannerScreen({super.key, CameraService? cameraService})
      : _cameraService = cameraService;

  final CameraService? _cameraService;

  @override
  State<FishScannerScreen> createState() => _FishScannerScreenState();
}

class _FishScannerScreenState extends State<FishScannerScreen>
    with WidgetsBindingObserver {
  late final CameraService _cameraService;
  late final FrameProcessor _frameProcessor;
  late final Future<void> _initFuture;

  /// Stub detection result shown in the bottom info panel.
  /// TODO(#22): replace with live [DetectionResult] from ML pipeline.
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
    WidgetsBinding.instance.addObserver(this);
    _initFuture = _initCamera();
  }

  Future<void> _initCamera() async {
    await _cameraService.initialize();
    if (_cameraService.errorMessage.value == null) {
      _frameProcessor.start(_cameraService.imageStream);
    }
    _cameraService.errorMessage.addListener(_onCameraError);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _frameProcessor.stop();
        _cameraService.stopImageStream();
      case AppLifecycleState.resumed:
        _cameraService.startImageStream();
        if (_cameraService.controller?.value.isInitialized ?? false) {
          _frameProcessor.start(_cameraService.imageStream);
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
    _frameProcessor.dispose();
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
    required this.stubSpecies,
    required this.errorMessage,
    required this.colorScheme,
  });

  final CameraController controller;

  /// Stub species info shown until Issue #22 wires real detections.
  /// TODO(#22): replace with a stream of live [DetectionResult]s.
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

        return Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1 — full-bleed camera preview.
            CameraPreview(controller),

            // Layer 2 — bounding box overlay (painter implemented in Issue #22).
            // TODO(#22): replace with FishOverlayPainter CustomPaint widget.
            IgnorePointer(
              child: Container(color: Colors.transparent),
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
                  child: SpeciesInfoCard(speciesInfo: stubSpecies),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}