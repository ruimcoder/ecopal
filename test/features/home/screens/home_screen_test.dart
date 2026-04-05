import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecopal/features/home/screens/home_screen.dart';
import 'package:ecopal/features/home/widgets/skill_card.dart';
import 'package:ecopal/core/routing/app_router.dart';

Widget _wrap(Widget child) => MaterialApp(
      onGenerateRoute: AppRouter.generateRoute,
      home: child,
    );

void main() {
  group('HomeScreen', () {
    testWidgets('renders app title and subtitle', (tester) async {
      await tester.pumpWidget(_wrap(const HomeScreen()));
      await tester.pump();
      expect(find.text('ecopal'), findsOneWidget);
      expect(find.text('Choose your eco-skill'), findsOneWidget);
    });

    testWidgets('shows Fish Scanner card as available', (tester) async {
      await tester.pumpWidget(_wrap(const HomeScreen()));
      await tester.pump();
      expect(find.text('Fish Scanner'), findsOneWidget);
    });

    testWidgets('shows coming-soon skills', (tester) async {
      await tester.pumpWidget(_wrap(const HomeScreen()));
      await tester.pump();
      expect(find.text('Plastic Detector'), findsOneWidget);
      expect(find.text('Bird Watcher'), findsOneWidget);
      expect(find.text('Carbon Footprint'), findsOneWidget);
    });

    testWidgets('shows Soon badge for unavailable skills', (tester) async {
      await tester.pumpWidget(_wrap(const HomeScreen()));
      await tester.pump();
      expect(find.text('Soon'), findsNWidgets(3));
    });

    testWidgets('Fish Scanner card pushes a new route', (tester) async {
      await tester.pumpWidget(_wrap(const HomeScreen()));
      await tester.pump();
      // Navigator starts with only the home route (cannot pop)
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      expect(nav.canPop(), isFalse);
      await tester.tap(find.text('Fish Scanner'));
      await tester.pump(); // start animation — new route is now on the stack
      expect(nav.canPop(), isTrue);
    });
  });

  group('SkillCard', () {
    testWidgets('available card shows arrow icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SkillCard(
              skill: const EcoSkill(
                id: 'test',
                title: 'Test Skill',
                description: 'desc',
                icon: Icons.abc,
                route: '/test',
              ),
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsOneWidget);
    });

    testWidgets('unavailable card shows Soon badge and no arrow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SkillCard(
              skill: const EcoSkill(
                id: 'test',
                title: 'Coming Skill',
                description: 'desc',
                icon: Icons.abc,
                route: '/test',
                isAvailable: false,
              ),
              onTap: null,
            ),
          ),
        ),
      );
      expect(find.text('Soon'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNothing);
    });

    testWidgets('unavailable card onTap is ignored', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SkillCard(
              skill: const EcoSkill(
                id: 'test',
                title: 'Locked',
                description: 'desc',
                icon: Icons.abc,
                route: '/test',
                isAvailable: false,
              ),
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Locked'));
      expect(tapped, isFalse);
    });
  });
}
