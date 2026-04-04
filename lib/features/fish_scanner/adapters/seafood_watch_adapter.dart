import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/species_cache_db.dart';
import '../models/detection_result.dart';

/// HTTP adapter for Seafood Watch sustainability ratings.
///
/// Uses cache-first lookup via [SpeciesCacheDb]. On a cache miss:
/// - **Mock mode** (default, [useMockData] = `true`): returns a hardcoded
///   rating from [_mockRatings]. Use this until the API license is granted.
/// - **Live mode** ([useMockData] = `false`): calls the Seafood Watch REST API.
///   Disabled until the commercial license is approved — see TODO(#5).
///
/// On any network failure in live mode the adapter returns
/// [SeafoodWatchRating.notRated].
class SeafoodWatchAdapter {
  SeafoodWatchAdapter({
    this.useMockData = true,
    http.Client? httpClient,
    SpeciesCacheDb? cacheDb,
  })  : _http = httpClient ?? http.Client(),
        _cache = cacheDb ?? SpeciesCacheDb.instance;

  final bool useMockData;
  final http.Client _http;
  final SpeciesCacheDb _cache;

  static const String _apiBase =
      'https://api.seafoodwatch.org/business/recommendations';

  /// Hardcoded ratings covering all four [SeafoodWatchRating] values.
  ///
  /// Used in mock mode until live API is enabled (see TODO(#5)).
  static const Map<String, SeafoodWatchRating> _mockRatings = {
    // Best Choice
    'Oncorhynchus mykiss': SeafoodWatchRating.bestChoice, // Rainbow Trout
    'Salmo salar': SeafoodWatchRating.bestChoice, // Atlantic Salmon (farmed)
    'Clupea harengus': SeafoodWatchRating.bestChoice, // Atlantic Herring
    'Engraulis encrasicolus': SeafoodWatchRating.bestChoice, // European Anchovy
    'Sardina pilchardus': SeafoodWatchRating.bestChoice, // European Sardine
    'Mytilus edulis': SeafoodWatchRating.bestChoice, // Blue Mussel
    'Crassostrea gigas': SeafoodWatchRating.bestChoice, // Pacific Oyster
    // Good Alternative
    'Gadus morhua': SeafoodWatchRating.goodAlternative, // Atlantic Cod
    'Melanogrammus aeglefinus':
        SeafoodWatchRating.goodAlternative, // Haddock
    'Pleuronectes platessa':
        SeafoodWatchRating.goodAlternative, // European Plaice
    'Solea solea': SeafoodWatchRating.goodAlternative, // Common Sole
    'Pollachius virens': SeafoodWatchRating.goodAlternative, // Saithe/Pollock
    'Merluccius merluccius':
        SeafoodWatchRating.goodAlternative, // European Hake
    // Avoid
    'Thunnus thynnus': SeafoodWatchRating.avoid, // Atlantic Bluefin Tuna
    'Xiphias gladius': SeafoodWatchRating.avoid, // Swordfish
    'Makaira nigricans': SeafoodWatchRating.avoid, // Atlantic Blue Marlin
    'Dissostichus eleginoides': SeafoodWatchRating.avoid, // Patagonian Toothfish
    'Lamna nasus': SeafoodWatchRating.avoid, // Porbeagle Shark
    'Scyliorhinus canicula': SeafoodWatchRating.avoid, // Small-spotted Catshark
    // Not Rated (insufficient data)
    'Cottus gobio': SeafoodWatchRating.notRated, // Bullhead
    'Anguilla anguilla': SeafoodWatchRating.notRated, // European Eel
  };

  /// Returns the Seafood Watch rating for [scientificName].
  ///
  /// Lookup order:
  /// 1. Fresh cache entry in [SpeciesCacheDb] (cache-first).
  /// 2. [_mockRatings] when [useMockData] is `true`.
  /// 3. Live Seafood Watch API when [useMockData] is `false`.
  ///
  /// On network failure returns [SeafoodWatchRating.notRated].
  Future<SeafoodWatchRating> getRating(String scientificName) async {
    final cached = await _cache.lookup(scientificName, 'en');
    if (cached != null) return cached.rating;

    if (useMockData) {
      final rating =
          _mockRatings[scientificName] ?? SeafoodWatchRating.notRated;
      await _storeRating(scientificName, rating);
      return rating;
    }

    return _fetchAndCache(scientificName);
  }

  Future<SeafoodWatchRating> _fetchAndCache(String scientificName) async {
    try {
      final rating = await _fetchFromApi(scientificName);
      await _storeRating(scientificName, rating);
      return rating;
    } on Exception catch (e) {
      debugPrint('SeafoodWatchAdapter: fetch failed for $scientificName: $e');
      return SeafoodWatchRating.notRated;
    }
  }

  Future<SeafoodWatchRating> _fetchFromApi(String scientificName) async {
    // TODO(#5): Remove guard and enable this code path once the Seafood Watch
    // API commercial license is granted.
    // TODO(#30): Add certificate pinning to [_http] before enabling live
    // requests in production.
    final uri = Uri.parse(
      '$_apiBase?query=${Uri.encodeQueryComponent(scientificName)}',
    );
    final response = await _http
        .get(uri)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return SeafoodWatchRating.notRated;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseApiResponse(body);
  }

  SeafoodWatchRating _parseApiResponse(Map<String, dynamic> body) {
    final ratingStr =
        (body['recommendations'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .firstOrNull?['rating'] as String?;
    return switch (ratingStr?.toLowerCase()) {
      'best choice' => SeafoodWatchRating.bestChoice,
      'good alternative' => SeafoodWatchRating.goodAlternative,
      'avoid' => SeafoodWatchRating.avoid,
      _ => SeafoodWatchRating.notRated,
    };
  }

  Future<void> _storeRating(
    String scientificName,
    SeafoodWatchRating rating,
  ) async {
    await _cache.store(
      SpeciesInfo(
        scientificName: scientificName,
        rating: rating,
        commonNames: const {},
      ),
    );
  }
}
