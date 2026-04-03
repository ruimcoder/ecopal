// Skill routing — dispatches to the correct skill screen.
// Currently only Fish Scanner exists. Add new skills here.
import 'package:flutter/material.dart';
import '../../features/fish_scanner/screens/fish_scanner_screen.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
      case '/fish-scanner':
        return MaterialPageRoute(
          builder: (_) => const FishScannerScreen(),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const FishScannerScreen(),
        );
    }
  }
}
