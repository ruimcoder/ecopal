import 'package:ecopal/features/fish_scanner/models/detection_result.dart';
import 'package:ecopal/features/fish_scanner/widgets/rating_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  group('RatingBadge', () {
    for (final entry in {
      SeafoodWatchRating.bestChoice: const Color(0xFF4CAF50),
      SeafoodWatchRating.goodAlternative: const Color(0xFFFFC107),
      SeafoodWatchRating.avoid: const Color(0xFFF44336),
      SeafoodWatchRating.notRated: const Color(0xFF9E9E9E),
    }.entries) {
      testWidgets('renders correct colour for ${entry.key.name}',
          (tester) async {
    await tester.pumpWidget(wrap(RatingBadge(rating: entry.key)));

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(RatingBadge),
            matching: find.byType(Container),
          ),
        );
        final decoration = container.decoration as BoxDecoration;
        expect(decoration.color, entry.value);
      });
    }

    testWidgets('shows label text', (tester) async {
      await tester.pumpWidget(
        wrap(const RatingBadge(rating: SeafoodWatchRating.avoid)),
      );
      expect(find.text('AVOID'), findsOneWidget);
    });

    testWidgets('has Semantics wrapper with label', (tester) async {
      await tester.pumpWidget(
        wrap(const RatingBadge(rating: SeafoodWatchRating.bestChoice)),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Seafood Watch rating')),
        findsOneWidget,
      );
    });
  });
}
