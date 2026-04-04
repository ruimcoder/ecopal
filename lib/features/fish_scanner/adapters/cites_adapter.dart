import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../data/species_cache_db.dart';

/// CITES Appendix listing for a species.
enum CitesAppendix {
  appendixI,
  appendixII,
  appendixIII,
  notListed;

  /// i18n key used for badge labels.
  String get i18nKey => switch (this) {
        CitesAppendix.appendixI => 'citesBadgeAppendixI',
        CitesAppendix.appendixII => 'citesBadgeAppendixII',
        CitesAppendix.appendixIII => 'citesBadgeAppendixIII',
        CitesAppendix.notListed => 'citesBadgeNotListed',
      };
}

/// Adapter that resolves the CITES Appendix listing for a scientific name.
///
/// Results are cached in a `cites_cache` SQLite table (7-day TTL).
/// Set [useMockData] to `false` and supply an [apiToken] once the CITES
/// Species+ commercial licence is granted (Issue #6).
class CitesAdapter {
  CitesAdapter({
    this.useMockData = true,
    this.apiToken = '',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final bool useMockData;
  final String apiToken;
  final http.Client _http;

  static const int _ttlSeconds = 604800; // 7 days

  // ---------------------------------------------------------------------------
  // Mock data — ~15 well-known CITES-listed fish species
  // ---------------------------------------------------------------------------
  static const Map<String, CitesAppendix> _mockData = {
    // Appendix I — commercial trade banned
    'Pristis pristis': CitesAppendix.appendixI, // Largetooth sawfish
    'Pristis pectinata': CitesAppendix.appendixI, // Smalltooth sawfish
    'Carcharodon carcharias': CitesAppendix.appendixII, // Great white shark
    'Rhincodon typus': CitesAppendix.appendixII, // Whale shark
    'Cetorhinus maximus': CitesAppendix.appendixII, // Basking shark
    // Appendix II — trade regulated
    'Anguilla anguilla': CitesAppendix.appendixII, // European eel
    'Hippocampus hippocampus': CitesAppendix.appendixII, // Short-snouted seahorse
    'Hippocampus guttulatus': CitesAppendix.appendixII, // Long-snouted seahorse
    'Manta birostris': CitesAppendix.appendixII, // Giant oceanic manta ray
    'Sphyrna lewini': CitesAppendix.appendixII, // Scalloped hammerhead
    'Sphyrna mokarran': CitesAppendix.appendixII, // Great hammerhead
    'Lamna nasus': CitesAppendix.appendixII, // Porbeagle
    'Isurus oxyrinchus': CitesAppendix.appendixII, // Shortfin mako
    // Not listed in CITES (but conservation-notable)
    'Thunnus thynnus': CitesAppendix.notListed, // Atlantic Bluefin tuna
    'Gadus morhua': CitesAppendix.notListed, // Atlantic cod
  };

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns the [CitesAppendix] for [scientificName].
  ///
  /// Checks the local cache first; falls back to mock/real API on a miss.
  /// Returns [CitesAppendix.notListed] for any unknown species.
  Future<CitesAppendix> getAppendix(String scientificName) async {
    final cached = await _lookupCache(scientificName);
    if (cached != null) return cached;

    final appendix = useMockData
        ? _mockData[scientificName] ?? CitesAppendix.notListed
        : await _fetchFromApi(scientificName);

    await _storeCache(scientificName, appendix);
    return appendix;
  }

  // ---------------------------------------------------------------------------
  // Cache helpers (cites_cache table, created lazily alongside species_cache)
  // ---------------------------------------------------------------------------

  Future<Database> get _db async {
    // Reuse the singleton opened by SpeciesCacheDb; ensure it is initialised.
    final speciesDb = SpeciesCacheDb.instance;
    // init() is idempotent — safe to call multiple times.
    await speciesDb.init();
    final db = speciesDb.rawDatabase;

    // Create cites_cache table if it does not exist yet.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cites_cache (
        scientific_name TEXT PRIMARY KEY,
        appendix        TEXT NOT NULL,
        fetched_at      INTEGER NOT NULL,
        expires_at      INTEGER NOT NULL
      )
    ''');
    return db;
  }

  Future<CitesAppendix?> _lookupCache(String scientificName) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rows = await db.query(
      'cites_cache',
      where: 'scientific_name = ? AND expires_at > ?',
      whereArgs: [scientificName, now],
    );
    if (rows.isEmpty) return null;
    return _parseAppendix(rows.first['appendix'] as String);
  }

  Future<void> _storeCache(
    String scientificName,
    CitesAppendix appendix,
  ) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.insert(
      'cites_cache',
      {
        'scientific_name': scientificName,
        'appendix': appendix.name,
        'fetched_at': now,
        'expires_at': now + _ttlSeconds,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------------
  // Real API — TODO(#6): enable once CITES Species+ licence is granted
  // ---------------------------------------------------------------------------

  Future<CitesAppendix> _fetchFromApi(String scientificName) async {
    // TODO(#6): Remove assertion and wire up production token via secure proxy.
    assert(apiToken.isNotEmpty, 'CITES API token must be set (Issue #6)');

    final uri = Uri.https(
      'api.speciesplus.net',
      '/api/v1/taxon_concepts',
      {'name': scientificName},
    );

    final response = await _http.get(
      uri,
      headers: {'X-Authentication-Token': apiToken},
    );

    if (response.statusCode != 200) return CitesAppendix.notListed;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final concepts = body['taxon_concepts'] as List<dynamic>? ?? [];
    if (concepts.isEmpty) return CitesAppendix.notListed;

    final concept = concepts.first as Map<String, dynamic>;
    final listings = concept['cites_listings'] as List<dynamic>? ?? [];
    if (listings.isEmpty) return CitesAppendix.notListed;

    // Pick the highest (most restrictive) appendix found.
    CitesAppendix result = CitesAppendix.notListed;
    for (final l in listings) {
      final a = _parseAppendixRoman(
        (l as Map<String, dynamic>)['appendix'] as String? ?? '',
      );
      if (a.index < result.index) result = a;
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Parsers
  // ---------------------------------------------------------------------------

  CitesAppendix _parseAppendix(String name) =>
      CitesAppendix.values.firstWhere(
        (v) => v.name == name,
        orElse: () => CitesAppendix.notListed,
      );

  CitesAppendix _parseAppendixRoman(String roman) => switch (roman) {
        'I' => CitesAppendix.appendixI,
        'II' => CitesAppendix.appendixII,
        'III' => CitesAppendix.appendixIII,
        _ => CitesAppendix.notListed,
      };

  /// Releases the underlying HTTP client. Call when the adapter is no longer
  /// needed to avoid resource leaks.
  @mustCallSuper
  void dispose() => _http.close();
}
