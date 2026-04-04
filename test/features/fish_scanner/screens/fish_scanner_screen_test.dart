import 'package:ecopal/features/fish_scanner/screens/fish_scanner_screen.dart';
import 'package:ecopal/features/fish_scanner/services/camera_service.dart';
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

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

  // TODO(#22): FishOverlayPainter wiring tests will be added when
  // FishOverlayPainter is introduced in Issue #22.
}