import 'package:flutter/material.dart';

import '../models/detection_result.dart';

/// Paints bounding-box overlays for fish detections on a [CustomPaint] canvas.
///
/// Each [DetectionResult] is drawn as a rounded-rectangle border coloured by
/// its [SeafoodWatchRating], plus a pill-shaped label above the box showing the
/// species common name and rating label.
///
/// [detections] hold normalised bounding boxes (0.0–1.0 in both axes).
/// [previewSize] is the logical size of the camera preview widget; the painter
/// scales each bounding box to actual canvas pixels before drawing.
class FishOverlayPainter extends CustomPainter {
  const FishOverlayPainter({
    required this.detections,
    required this.previewSize,
  });

  final List<DetectionResult> detections;
  final Size previewSize;

  static const double _strokeWidth = 2.5;
  static const double _cornerRadius = 8.0;
  static const double _labelFontSize = 12.0;
  static const double _labelPadH = 6.0;
  static const double _labelPadV = 3.0;
  static const double _labelGap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Scale factors from normalised (0–1) to canvas pixels.
    final scaleX = size.width;
    final scaleY = size.height;

    for (final detection in detections) {
      final box = detection.boundingBox;
      final color =
          detection.speciesInfo?.rating.colour ?? Colors.grey;

      // Scale normalised rect to canvas coordinates.
      final rect = Rect.fromLTWH(
        box.left * scaleX,
        box.top * scaleY,
        box.width * scaleX,
        box.height * scaleY,
      );
      final rrect = RRect.fromRectAndRadius(
        rect,
        const Radius.circular(_cornerRadius),
      );

      // Bounding-box border.
      final borderPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth;
      canvas.drawRRect(rrect, borderPaint);

      // Pill label.
      _drawLabel(canvas, detection, rect, color);
    }
  }

  void _drawLabel(
    Canvas canvas,
    DetectionResult detection,
    Rect boxRect,
    Color color,
  ) {
    final speciesInfo = detection.speciesInfo;
    final displayName =
        speciesInfo?.commonName('en') ?? detection.scientificName;
    final rating = speciesInfo?.rating;
    final ratingLabel = rating?.label ?? '';

    // Build text spans: bold species name + normal rating label.
    final nameSpan = TextSpan(
      text: displayName,
      style: const TextStyle(
        color: Colors.white,
        fontSize: _labelFontSize,
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),
    );
    final ratingSpan = TextSpan(
      text: '\n$ratingLabel',
      style: const TextStyle(
        color: Colors.white,
        fontSize: _labelFontSize - 1,
        fontWeight: FontWeight.normal,
        height: 1.3,
      ),
    );

    final combinedSpan = TextSpan(
      children: [nameSpan, if (ratingLabel.isNotEmpty) ratingSpan],
    );

    final textPainter = TextPainter(
      text: combinedSpan,
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout();

    final labelW = textPainter.width + _labelPadH * 2;
    final labelH = textPainter.height + _labelPadV * 2;

    // Position the pill above the bounding box; clamp to top of canvas.
    final pillLeft = boxRect.left.clamp(0.0, double.infinity);
    final pillTop = (boxRect.top - labelH - _labelGap).clamp(
      0.0,
      double.infinity,
    );
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pillLeft, pillTop, labelW, labelH),
      const Radius.circular(6.0),
    );

    // Background fill.
    final bgPaint = Paint()
      ..color = color.withAlpha(204) // ~80% opacity
      ..style = PaintingStyle.fill;
    canvas.drawRRect(pillRect, bgPaint);

    // Text.
    textPainter.paint(
      canvas,
      Offset(pillLeft + _labelPadH, pillTop + _labelPadV),
    );
  }

  @override
  bool shouldRepaint(FishOverlayPainter oldDelegate) =>
      oldDelegate.detections != detections;
}
