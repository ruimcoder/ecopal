import 'package:flutter/material.dart';

import '../models/detection_result.dart';

/// A compact coloured pill badge displaying a [SeafoodWatchRating].
///
/// Uses the exact Seafood Watch colour palette. Suitable for use
/// beside bounding boxes and within info cards.
class RatingBadge extends StatelessWidget {
  const RatingBadge({
    super.key,
    required this.rating,
  });

  final SeafoodWatchRating rating;

  @override
  Widget build(BuildContext context) {
    final colour = rating.colour;
    final icon = rating.icon;
    // TODO(#27): AppLocalizations — rating label
    final label = rating.label;

    return Semantics(
      label: 'Seafood Watch rating: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              icon,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
