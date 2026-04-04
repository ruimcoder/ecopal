import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/detection_result.dart';

/// Local SQLite database for caching species conservation data.
///
/// Access via [SpeciesCacheDb.instance]. Call [init] once at app startup
/// before using any other methods.
class SpeciesCacheDb {
  SpeciesCacheDb._();

  /// Singleton instance.
  static final SpeciesCacheDb instance = SpeciesCacheDb._();

  Database? _db;

  /// Cache TTL in seconds (7 days).
  static const int _ttlSeconds = 604800;

  static const String _createSpeciesCache = '''
    CREATE TABLE species_cache (
      scientific_name TEXT PRIMARY KEY,
      seafood_watch_rating TEXT NOT NULL,
      fishbase_code   INTEGER,
      fetched_at      INTEGER NOT NULL,
      expires_at      INTEGER NOT NULL
    )
  ''';

  static const String _createCommonNames = '''
    CREATE TABLE common_names (
      scientific_name TEXT NOT NULL,
      language_code   TEXT NOT NULL,
      common_name     TEXT NOT NULL,
      PRIMARY KEY (scientific_name, language_code)
    )
  ''';

  /// Opens (or creates) the database.
  ///
  /// If [dbPath] is omitted the database is placed at
  /// `getApplicationDocumentsDirectory()/ecopal.db`.
  /// Pass [inMemoryDatabasePath] from `sqflite_common_ffi` for testing.
  Future<void> init({String? dbPath}) async {
    if (_db != null) return;
    final resolvedPath = dbPath ?? await _defaultDbPath();
    _db = await openDatabase(
      resolvedPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(_createSpeciesCache);
        await db.execute(_createCommonNames);
      },
    );
  }

  /// Exposes the underlying [Database] for adapters that need to create
  /// additional tables in the same file (e.g. [CitesAdapter]).
  ///
  /// Callers must ensure [init] has been called first.
  Database get rawDatabase {
    assert(_db != null, 'SpeciesCacheDb.init() must be called before accessing rawDatabase');
    return _db!;
  }

  /// Returns the default production database path.
  Future<String> _defaultDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/ecopal.db';
  }

  /// Looks up a cached [SpeciesInfo] by [scientificName].
  ///
  /// Returns `null` on a cache miss or when the cached entry has exceeded
  /// the 7-day TTL. All stored common names are included in the result.
  Future<SpeciesInfo?> lookup(
    String scientificName,
    String languageCode,
  ) async {
    final db = _db!;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final rows = await db.query(
      'species_cache',
      where: 'scientific_name = ?',
      whereArgs: [scientificName],
    );

    if (rows.isEmpty) return null;
    final row = rows.first;

    if ((row['expires_at'] as int) < now) return null;

    final nameRows = await db.query(
      'common_names',
      where: 'scientific_name = ?',
      whereArgs: [scientificName],
    );

    final commonNames = <String, String>{
      for (final r in nameRows)
        r['language_code'] as String: r['common_name'] as String,
    };

    return SpeciesInfo(
      scientificName: scientificName,
      rating: _parseRating(row['seafood_watch_rating'] as String),
      commonNames: commonNames,
      fishbaseCode: row['fishbase_code'] as int?,
    );
  }

  /// Upserts [species] into both `species_cache` and `common_names` tables.
  Future<void> store(SpeciesInfo species) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _storeInternal(
      species,
      fetchedAt: now,
      expiresAt: now + _ttlSeconds,
    );
  }

  /// Stores [species] with explicit [fetchedAt] and [expiresAt] timestamps.
  ///
  /// Intended for use in tests only.
  @visibleForTesting
  Future<void> storeWithTimestamps(
    SpeciesInfo species, {
    required int fetchedAt,
    required int expiresAt,
  }) async {
    await _storeInternal(species, fetchedAt: fetchedAt, expiresAt: expiresAt);
  }

  Future<void> _storeInternal(
    SpeciesInfo species, {
    required int fetchedAt,
    required int expiresAt,
  }) async {
    final db = _db!;
    await db.insert(
      'species_cache',
      {
        'scientific_name': species.scientificName,
        'seafood_watch_rating': species.rating.name,
        'fishbase_code': species.fishbaseCode,
        'fetched_at': fetchedAt,
        'expires_at': expiresAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    for (final entry in species.commonNames.entries) {
      await db.insert(
        'common_names',
        {
          'scientific_name': species.scientificName,
          'language_code': entry.key,
          'common_name': entry.value,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Deletes all rows from `species_cache` whose `expires_at` is in the past.
  Future<void> clearExpired() async {
    final db = _db!;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.delete(
      'species_cache',
      where: 'expires_at < ?',
      whereArgs: [now],
    );
  }

  /// Closes the underlying database connection.
  ///
  /// Useful in tests to reset state between runs.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Parses a stored rating string back to [SeafoodWatchRating].
  SeafoodWatchRating _parseRating(String value) {
    return SeafoodWatchRating.values.firstWhere(
      (r) => r.name == value,
      orElse: () => SeafoodWatchRating.notRated,
    );
  }
}
