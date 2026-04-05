// Skill routing — dispatches to the correct skill screen.
// To add a new skill: add a route case below and a card in HomeScreen._skills.
import 'package:flutter/material.dart';
import '../../features/fish_scanner/screens/fish_scanner_screen.dart';
import '../../features/home/screens/home_screen.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case '/fish-scanner':
        return MaterialPageRoute(builder: (_) => const FishScannerScreen());
      default:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
    }
  }
}
