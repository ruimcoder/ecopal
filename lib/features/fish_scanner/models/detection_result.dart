import 'package:flutter/material.dart';

/// Result of fish species detection from a single camera frame.
class DetectionResult {
  const DetectionResult({
    required this.scientificName,
    required this.confidence,
    required this.boundingBox,
    this.speciesInfo,
  });

  final String scientificName;
  final double confidence;

  /// Normalised bounding box (0.0–1.0 in both axes).
  final Rect boundingBox;

  /// Null while species lookup is in progress.
  final SpeciesInfo? speciesInfo;
}

/// Conservation and common name data for a detected species.
class SpeciesInfo {
  const SpeciesInfo({
    required this.scientificName,
    required this.rating,
    required this.commonNames,
    this.fishbaseCode,
    this.citesAppendix,
    this.osparListed = false,
    this.helcomListed = false,
  });

  final String scientificName;
  final SeafoodWatchRating rating;
  final Map<String, String> commonNames; // ISO 639-1 → name
  final int? fishbaseCode;
  final String? citesAppendix; // 'I', 'II', 'III' or null
  final bool osparListed;
  final bool helcomListed;

  String commonName(String languageCode) =>
      commonNames[languageCode] ?? commonNames['en'] ?? scientificName;
}

/// Seafood Watch sustainability rating.
enum SeafoodWatchRating {
  bestChoice,
  goodAlternative,
  avoid,
  notRated;

  Color get colour => switch (this) {
        SeafoodWatchRating.bestChoice => const Color(0xFF4CAF50),
        SeafoodWatchRating.goodAlternative => const Color(0xFFFFC107),
        SeafoodWatchRating.avoid => const Color(0xFFF44336),
        SeafoodWatchRating.notRated => const Color(0xFF9E9E9E),
      };

  String get label => switch (this) {
        SeafoodWatchRating.bestChoice => 'BEST CHOICE',
        SeafoodWatchRating.goodAlternative => 'GOOD ALTERNATIVE',
        SeafoodWatchRating.avoid => 'AVOID',
        SeafoodWatchRating.notRated => 'NOT RATED',
      };

  String get icon => switch (this) {
        SeafoodWatchRating.bestChoice => '✅',
        SeafoodWatchRating.goodAlternative => '⚠️',
        SeafoodWatchRating.avoid => '🚫',
        SeafoodWatchRating.notRated => '❓',
      };
}
