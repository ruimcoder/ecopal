import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../features/fish_scanner/screens/fish_scanner_screen.dart';
import 'theme/app_theme.dart';

class EcopalApp extends StatelessWidget {
  const EcopalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ecopal',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('pt'),
        Locale('es'),
        Locale('fr'),
        Locale('de'),
      ],
      home: const FishScannerScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
