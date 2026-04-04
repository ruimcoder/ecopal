import 'package:ecopal/features/fish_scanner/models/detection_result.dart';
import 'package:ecopal/features/fish_scanner/widgets/species_info_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  const species = SpeciesInfo(
    scientificName: 'Gadus morhua',
    rating: SeafoodWatchRating.goodAlternative,
    commonNames: {'en': 'Atlantic Cod'},
  );

  group('SpeciesInfoCard', () {
    testWidgets('displays scientific name', (tester) async {
      await tester.pumpWidget(wrap(const SpeciesInfoCard(speciesInfo: species)));
      expect(find.text('Gadus morhua'), findsOneWidget);
    });

    testWidgets('displays English common name', (tester) async {
      await tester.pumpWidget(wrap(const SpeciesInfoCard(speciesInfo: species)));
      expect(find.text('Atlantic Cod'), findsOneWidget);
    });

    testWidgets('falls back to scientific name when no en common name',
        (tester) async {
      const noEn = SpeciesInfo(
        scientificName: 'Thunnus albacares',
        rating: SeafoodWatchRating.notRated,
        commonNames: {'pt': 'Atum Amarelo'},
      );
      await tester.pumpWidget(wrap(const SpeciesInfoCard(speciesInfo: noEn)));
      // scientific name shown as fallback for both scientific and common name slots
      expect(find.text('Thunnus albacares'), findsWidgets);
    });

    testWidgets('contains a RatingBadge', (tester) async {
      await tester.pumpWidget(wrap(const SpeciesInfoCard(speciesInfo: species)));
      expect(find.byType(SpeciesInfoCard), findsOneWidget);
      // RatingBadge must be a descendant
      expect(
        find.descendant(
          of: find.byType(SpeciesInfoCard),
          matching: find.text('GOOD ALTERNATIVE'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('has Semantics wrapper', (tester) async {
      await tester.pumpWidget(wrap(const SpeciesInfoCard(speciesInfo: species)));
      expect(
        find.bySemanticsLabel(RegExp(r'Species: Gadus morhua')),
        findsOneWidget,
      );
    });
  });
}
