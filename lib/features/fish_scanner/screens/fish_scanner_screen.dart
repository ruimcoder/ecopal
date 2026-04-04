import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/camera_service.dart';

/// Main Fish Scanner screen.
/// Hosts the camera preview and overlay stack.
class FishScannerScreen extends StatefulWidget {
  const FishScannerScreen({super.key});

  @override
  State<FishScannerScreen> createState() => _FishScannerScreenState();
}

class _FishScannerScreenState extends State<FishScannerScreen>
    with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFuture = _cameraService.initialize();
    _cameraService.errorMessage.addListener(_onCameraError);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _cameraService.stopImageStream();
      case AppLifecycleState.resumed:
        _cameraService.startImageStream();
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
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          // TODO(#27): replace with AppLocalizations.of(context)!.scannerTitle
          'ecopal',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            // TODO(#27): AppLocalizations — switch camera tooltip
            tooltip: 'Switch camera',
            icon: Icon(Icons.flip_camera_android, color: colorScheme.onSurface),
            onPressed: () async {
              await _cameraService.switchCamera();
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            icon: Icon(Icons.settings, color: colorScheme.onSurface),
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
            return Center(
              child: CircularProgressIndicator(color: colorScheme.primary),
            );
          }

          final error = _cameraService.errorMessage.value;
          if (error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.no_photography,
                      size: 64,
                      color: colorScheme.onSurface.withAlpha(128),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      // TODO(#27): AppLocalizations — camera error heading
                      'Camera unavailable',
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
                    FilledButton.icon(
                      onPressed: openAppSettings,
                      icon: const Icon(Icons.settings),
                      // TODO(#27): AppLocalizations — open settings button
                      label: const Text('Open Settings'),
                    ),
                  ],
                ),
              ),
            );
          }

          final controller = _cameraService.controller;
          if (controller == null || !controller.value.isInitialized) {
            return Center(
              child: CircularProgressIndicator(color: colorScheme.primary),
            );
          }

          return AnimatedBuilder(
            animation: _cameraService.errorMessage,
            builder: (context, _) {
              final liveError = _cameraService.errorMessage.value;
              if (liveError != null) {
                return Center(
                  child: Text(
                    liveError,
                    style: TextStyle(color: colorScheme.error),
                  ),
                );
              }
              return CameraPreview(_cameraService.controller!);
            },
          );
        },
      ),
    );
  }
}