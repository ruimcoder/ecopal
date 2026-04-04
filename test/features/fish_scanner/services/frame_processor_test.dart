import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:ecopal/features/fish_scanner/services/frame_processor.dart';

import 'frame_processor_test.mocks.dart';

@GenerateMocks([CameraImage])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockCameraImage mockImage;

  setUp(() {
    mockImage = MockCameraImage();
    when(mockImage.width).thenReturn(640);
    when(mockImage.height).thenReturn(480);
  });

  ProcessedFrame makeFrame(DateTime ts) => ProcessedFrame(
        bytes: Uint8List(4),
        width: 640,
        height: 480,
        format: 'RGBA',
        timestamp: ts,
      );

  group('FrameProcessor', () {
    test('frames are throttled to at most 5 fps', () async {
      var fakeNow = DateTime(2024);

      final processor = FrameProcessor(
        clock: () => fakeNow,
        converter: (_, ts) async => makeFrame(ts),
      );

      final streamCtrl = StreamController<CameraImage>.broadcast();
      processor.start(streamCtrl.stream);

      final received = <ProcessedFrame>[];
      processor.frames.listen(received.add);

      // Send 60 frames at ~60 fps (16 ms apart) spanning ~1 second.
      for (var i = 0; i < 60; i++) {
        streamCtrl.add(mockImage);
        // Allow the async converter to complete before advancing the clock.
        await Future<void>.delayed(Duration.zero);
        fakeNow = fakeNow.add(const Duration(milliseconds: 16));
      }

      // At 5 fps max, no more than 5 frames should have been emitted.
      expect(received.length, lessThanOrEqualTo(5));

      await processor.dispose();
      await streamCtrl.close();
    });

    test('ProcessedFrame carries correct width, height, and format', () async {
      final processor = FrameProcessor(
        converter: (image, ts) async => ProcessedFrame(
          bytes: Uint8List(4),
          width: image.width,
          height: image.height,
          format: 'RGBA',
          timestamp: ts,
        ),
      );

      final streamCtrl = StreamController<CameraImage>.broadcast();
      processor.start(streamCtrl.stream);

      final received = <ProcessedFrame>[];
      processor.frames.listen(received.add);

      streamCtrl.add(mockImage);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.first.width, equals(640));
      expect(received.first.height, equals(480));
      expect(received.first.format, equals('RGBA'));

      await processor.dispose();
      await streamCtrl.close();
    });

    test('stop() cancels the subscription and no more frames are emitted',
        () async {
      var fakeNow = DateTime(2024);

      final processor = FrameProcessor(
        clock: () => fakeNow,
        converter: (_, ts) async => makeFrame(ts),
      );

      final streamCtrl = StreamController<CameraImage>.broadcast();
      processor.start(streamCtrl.stream);

      final received = <ProcessedFrame>[];
      processor.frames.listen(received.add);

      // One frame before stop.
      streamCtrl.add(mockImage);
      await Future<void>.delayed(Duration.zero);

      processor.stop();

      // Advance time so throttling would not block a second frame if delivered.
      fakeNow = fakeNow.add(const Duration(seconds: 1));

      // Two frames after stop — subscription is cancelled, none should arrive.
      streamCtrl.add(mockImage);
      streamCtrl.add(mockImage);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));

      await processor.dispose();
      await streamCtrl.close();
    });
  });
}
