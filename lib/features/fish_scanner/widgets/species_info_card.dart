import 'package:flutter/material.dart';

import '../models/detection_result.dart';
import 'rating_badge.dart';

/// A semi-transparent card overlay that shows species information on the
/// scanner screen.
///
/// Displays the scientific name, English common name (from
/// [SpeciesInfo.commonNames]) and a [RatingBadge]. Designed to be readable
/// on top of a live camera feed.
class SpeciesInfoCard extends StatelessWidget {
  const SpeciesInfoCard({
    super.key,
    required this.speciesInfo,
  });

  final SpeciesInfo speciesInfo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // TODO(#27): AppLocalizations — use device locale for common name lookup
    final commonName =
        speciesInfo.commonNames['en'] ?? speciesInfo.scientificName;

    return Semantics(
      label: 'Species: ${speciesInfo.scientificName}, '
          'common name: $commonName, '
          'rating: ${speciesInfo.rating.label}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(178),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              speciesInfo.scientificName,
              style: textTheme.bodySmall?.copyWith(
                color: Colors.white70,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              commonName,
              style: textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            RatingBadge(rating: speciesInfo.rating),
          ],
        ),
      ),
    );
  }
}
