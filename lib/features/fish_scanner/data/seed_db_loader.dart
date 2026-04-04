import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Copies the bundled seed database to the app's documents directory on first
/// launch so that [SpeciesDb] (Issue #15) can open it without any network
/// access.
class SeedDbLoader {
  static const String _assetPath = 'assets/data/ecopal_seed.db';
  static const String _dbFileName = 'ecopal.db';

  /// Copies the bundled seed DB to `getApplicationDocumentsDirectory()/ecopal.db`
  /// only if the file does not already exist.
  static Future<void> copyToDocuments() async {
    final Directory docsDir = await getApplicationDocumentsDirectory();
    final File target = File('${docsDir.path}/$_dbFileName');

    if (target.existsSync()) {
      return;
    }

    final ByteData data = await rootBundle.load(_assetPath);
    await target.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
}
