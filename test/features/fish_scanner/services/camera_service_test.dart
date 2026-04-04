import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:permission_handler/permission_handler.dart';

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

  // Helpers
  const backCamera = CameraDescription(
    name: 'back',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );
  const frontCamera = CameraDescription(
    name: 'front',
    lensDirection: CameraLensDirection.front,
    sensorOrientation: 270,
  );

  PermissionRequester granted() =>
      () async => PermissionStatus.granted;

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

    test('initialize sets up controller when permission granted', () async {
      final mockController = MockCameraController();

      final service = CameraService(
        cameras: const [backCamera],
        permissionRequester: granted(),
        controllerFactory: (_) => mockController,
      );

      await service.initialize();

      expect(service.errorMessage.value, isNull);
      expect(service.controller, same(mockController));
      verify(mockController.initialize()).called(1);
      verify(mockController.startImageStream(any)).called(1);
    });

    test('initialize sets errorMessage when no cameras available', () async {
      final service = CameraService(
        cameras: const [],
        permissionRequester: granted(),
      );

      await service.initialize();

      expect(service.errorMessage.value, isNotNull);
      expect(service.errorMessage.value, contains('No cameras'));
    });

    test('initialize captures CameraException in errorMessage', () async {
      final mockController = MockCameraController();
      when(mockController.initialize()).thenThrow(
        CameraException('test', 'Test camera error'),
      );

      final service = CameraService(
        cameras: const [backCamera],
        permissionRequester: granted(),
        controllerFactory: (_) => mockController,
      );

      await service.initialize();

      expect(service.errorMessage.value, 'Test camera error');
    });

    test('dispose stops image stream if streaming', () async {
      final mockController = MockCameraController();

      final service = CameraService(
        cameras: const [backCamera],
        permissionRequester: granted(),
        controllerFactory: (_) => mockController,
      );

      await service.initialize();
      await service.dispose();

      verify(mockController.stopImageStream()).called(1);
      verify(mockController.dispose()).called(1);
    });

    test('switchCamera reinitialises with back camera when front is active',
        () async {
      final mockBack = MockCameraController();
      final mockFront = MockCameraController();

      final service = CameraService(
        cameras: const [backCamera, frontCamera],
        permissionRequester: granted(),
        controllerFactory: (desc) => desc.lensDirection ==
                CameraLensDirection.back
            ? mockBack
            : mockFront,
      );

      // Initialises on back camera.
      await service.initialize();

      verify(mockBack.initialize()).called(1);
      verifyNever(mockFront.initialize());

      // Switches to front camera.
      await service.switchCamera();

      // Old (back) controller must be stopped and disposed.
      verify(mockBack.stopImageStream()).called(1);
      verify(mockBack.dispose()).called(1);

      // New (front) controller must be initialised.
      verify(mockFront.initialize()).called(1);
      expect(service.controller, same(mockFront));
    });
  });
}
