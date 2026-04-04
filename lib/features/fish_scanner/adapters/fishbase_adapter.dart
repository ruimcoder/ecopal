import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/species_cache_db.dart';
import '../models/detection_result.dart';

/// HTTP adapter that fetches multilingual common names from the
/// FishBase rOpenSci API (https://fishbase.ropensci.org).
class FishBaseAdapter {
  FishBaseAdapter({
    http.Client? client,
    Duration rateLimitInterval = const Duration(seconds: 1),
  })  : _client = client ?? http.Client(),
        _rateLimitInterval = rateLimitInterval;

  final http.Client _client;
  final Duration _rateLimitInterval;

  static const Duration _timeout = Duration(seconds: 15);
  static const String _baseUrl = 'https://fishbase.ropensci.org';

  DateTime? _lastCallTime;

  /// Returns a `{languageCode: commonName}` map for [scientificName].
  ///
  /// Checks the local cache first. On a miss, queries FishBase for the
  /// SpecCode then fetches common names. The result is stored in the
  /// cache for subsequent calls.
  ///
  /// Always returns at least `{'en': scientificName}` on any failure.
  Future<Map<String, String>> getCommonNames(String scientificName) async {
    // Cache-first
    try {
      final cached =
          await SpeciesCacheDb.instance.lookup(scientificName, 'en');
      if (cached != null && cached.commonNames.isNotEmpty) {
        return Map<String, String>.from(cached.commonNames);
      }
    } on Exception catch (e) {
      debugPrint('FishBaseAdapter: cache lookup failed: $e');
    }

    try {
      final specCode = await getSpecCode(scientificName);
      if (specCode == null) {
        return {'en': scientificName};
      }

      await _enforceRateLimit();

      final uri = Uri.parse('$_baseUrl/common_names?SpecCode=$specCode');
      final response = await _client.get(uri).timeout(_timeout);

      if (response.statusCode != 200) {
        return {'en': scientificName};
      }

      final commonNames = _parseCommonNames(response.body);
      if (commonNames.isEmpty) {
        return {'en': scientificName};
      }

      await _cacheNames(scientificName, specCode, commonNames);
      return commonNames;
    } on Exception catch (e) {
      debugPrint('FishBaseAdapter: common names fetch failed for $scientificName: $e');
      return {'en': scientificName};
    }
  }

  /// Returns the FishBase `SpecCode` for [scientificName], or `null` on error.
  Future<int?> getSpecCode(String scientificName) async {
    final parts = scientificName.trim().split(' ');
    if (parts.length < 2) return null;

    final genus = parts[0];
    final species = parts.sublist(1).join(' ');

    try {
      await _enforceRateLimit();

      final uri = Uri.parse(
        '$_baseUrl/species'
        '?Genus=${Uri.encodeComponent(genus)}'
        '&Species=${Uri.encodeComponent(species)}',
      );
      final response = await _client.get(uri).timeout(_timeout);

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>?;
      if (data == null || data.isEmpty) return null;

      return (data.first as Map<String, dynamic>)['SpecCode'] as int?;
    } on Exception catch (e) {
      debugPrint('FishBaseAdapter: specCode lookup failed for $scientificName: $e');
      return null;
    }
  }

  Future<void> _enforceRateLimit() async {
    if (_lastCallTime != null) {
      final elapsed = DateTime.now().difference(_lastCallTime!);
      if (elapsed < _rateLimitInterval) {
        await Future.delayed(_rateLimitInterval - elapsed);
      }
    }
    _lastCallTime = DateTime.now();
  }

  Map<String, String> _parseCommonNames(String responseBody) {
    final commonNames = <String, String>{};
    try {
      final body = jsonDecode(responseBody) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>?;
      if (data == null) return commonNames;

      for (final item in data) {
        final map = item as Map<String, dynamic>;
        final fishbaseLang = map['Language'] as String?;
        final name = map['ComName'] as String?;
        if (fishbaseLang == null || name == null) continue;

        final isoCode = _fishBaseLangToIso(fishbaseLang);
        if (isoCode != null && !commonNames.containsKey(isoCode)) {
          commonNames[isoCode] = name;
        }
      }
    } on Exception catch (e) {
      debugPrint('FishBaseAdapter: JSON parse failed: $e');
    }
    return commonNames;
  }

  Future<void> _cacheNames(
    String scientificName,
    int specCode,
    Map<String, String> commonNames,
  ) async {
    try {
      final existing =
          await SpeciesCacheDb.instance.lookup(scientificName, 'en');
      await SpeciesCacheDb.instance.store(
        SpeciesInfo(
          scientificName: scientificName,
          rating: existing?.rating ?? SeafoodWatchRating.notRated,
          commonNames: commonNames,
          fishbaseCode: specCode,
        ),
      );
    } on Exception catch (e) {
      debugPrint('FishBaseAdapter: cache write failed: $e');
    }
  }

  static String? _fishBaseLangToIso(String language) {
    const mapping = <String, String>{
      'English': 'en',
      'Portuguese': 'pt',
      'Spanish': 'es',
      'French': 'fr',
      'German': 'de',
      'Italian': 'it',
      'Dutch': 'nl',
      'Russian': 'ru',
      'Chinese': 'zh',
      'Japanese': 'ja',
      'Arabic': 'ar',
      'Swedish': 'sv',
      'Norwegian': 'no',
      'Danish': 'da',
      'Finnish': 'fi',
      'Polish': 'pl',
      'Czech': 'cs',
      'Slovak': 'sk',
      'Hungarian': 'hu',
      'Romanian': 'ro',
      'Bulgarian': 'bg',
      'Croatian': 'hr',
      'Serbian': 'sr',
      'Greek': 'el',
      'Turkish': 'tr',
      'Korean': 'ko',
      'Vietnamese': 'vi',
      'Thai': 'th',
      'Indonesian': 'id',
      'Malay': 'ms',
      'Hebrew': 'he',
      'Hindi': 'hi',
    };
    return mapping[language];
  }
}
