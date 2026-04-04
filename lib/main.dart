import 'package:flutter/material.dart';
import 'core/app.dart';
import 'features/fish_scanner/data/seed_db_loader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SeedDbLoader.copyToDocuments();
  runApp(const EcopalApp());
}
