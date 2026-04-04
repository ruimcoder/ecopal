import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:ecopal/features/fish_scanner/services/camera_service.dart';

import 'camera_service_test.mocks.dart';

@GenerateMocks([CameraController])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Stub the camera platform channel so availableCameras() returns a known list.
  const MethodChannel cameraChannel =
      MethodChannel('plugins.flutter.io/camera');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cameraChannel, (call) async {
      if (call.method == 'availableCameras') {
        return [
          {
            'name': 'Camera 0',
            'lensFacing': 0, // back
            'sensorOrientation': 90,
          }
        ];
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cameraChannel, null);
  });

  group('CameraService', () {
    test('errorMessage is null initially', () {
      final service = CameraService();
      expect(service.errorMessage.value, isNull);
    });

    test('imageStream is a broadcast stream', () {
      final service = CameraService();
      expect(service.imageStream.isBroadcast, isTrue);
    });

    test('dispose completes without a controller', () async {
      final service = CameraService();
      await expectLater(service.dispose(), completes);
    });

    test('switchCamera completes when no cameras are available', () async {
      final service = CameraService();
      await expectLater(service.switchCamera(), completes);
    });

    test('MockCameraController is mockable', () {
      // Verify the generated mock can be instantiated and stubbed.
      final mock = MockCameraController();
      when(mock.initialize()).thenAnswer((_) async {});
      when(mock.dispose()).thenAnswer((_) async {});
      verifyNever(mock.initialize());
    });
  });
}
