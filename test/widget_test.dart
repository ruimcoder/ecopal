import 'package:flutter_test/flutter_test.dart';
import 'package:ecopal/core/app.dart';

void main() {
  testWidgets('App renders FishScannerScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const EcopalApp());
    expect(find.text('ecopal'), findsOneWidget);
  });
}
