import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/species_cache_db.dart';
import '../models/detection_result.dart';
import 'consent_service.dart';

/// iNaturalist Computer Vision API endpoint.
const String _kInatUrl =
    'https://api.inaturalist.org/v1/computervision/score_image';

/// HTTP timeout for the iNaturalist API call (LP-005).
const Duration _kTimeout = Duration(seconds: 15);

/// Scientific name used for the hardcoded mock result.
const String _kMockScientificName = 'Thunnus obesus';

/// Common name used for the hardcoded mock result.
const String _kMockCommonName = 'Bigeye Tuna';

/// Sends [frameBytes] to the iNaturalist API and returns the raw JSON body.
///
/// Returns `null` on network failure, timeout, or a non-200 status.
///
/// TODO(#30): add certificate pinning before production rollout.
Future<String?> _defaultSendFrame(Uint8List frameBytes) async {
  final client = http.Client();
  try {
    final request = http.MultipartRequest('POST', Uri.parse(_kInatUrl))
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          frameBytes,
          filename: 'frame.jpg',
        ),
      );
    final streamed =
        await client.send(request).timeout(_kTimeout); // LP-005
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      debugPrint(
        'CloudFallbackService: iNaturalist returned ${response.statusCode}',
      );
      return null;
    }
    return response.body;
  } on TimeoutException catch (e) {
    debugPrint('CloudFallbackService: request timed out — $e');
    return null;
  } on Exception catch (e) {
    debugPrint('CloudFallbackService: request failed — $e');
    return null;
  } finally {
    client.close();
  }
}

/// Identifies fish species via the iNaturalist Computer Vision API when
/// on-device inference confidence falls below threshold.
///
/// **Consent gate:** [identify] checks [ConsentService.requestConsentIfNeeded]
/// before any frame is transmitted. If consent is not granted the method
/// returns `null` immediately and no data leaves the device.
///
/// **Mock mode** (`useMockData = true`, the default): skips the HTTP call and
/// returns a hardcoded [DetectionResult] for [_kMockScientificName]. Use this
/// during development and in unit tests that do not need to exercise HTTP.
///
/// **Real mode** (`useMockData = false`): delegates the HTTP POST to
/// [sendFrameFn] (defaults to [_defaultSendFrame]), which sends [frameBytes]
/// to the iNaturalist Computer Vision API with a [_kTimeout] timeout.
/// The top taxon suggestion is parsed and cached in [SpeciesCacheDb].
///
/// The returned [DetectionResult] always has [DetectionResult.boundingBox] set
/// to [Rect.zero] — the caller is responsible for supplying the real box from
/// the original detection pipeline.
///
/// TODO(#30): add certificate pinning to iNaturalist calls before
/// production rollout — see [_defaultSendFrame].
class CloudFallbackService {
  CloudFallbackService({
    required this.consentService,
    required this.cacheDb,
    bool useMockData = true,
    Future<String?> Function(Uint8List)? sendFrameFn,
  })  : _useMockData = useMockData,
        _sendFrameFn = sendFrameFn ?? _defaultSendFrame;

  final ConsentService consentService;
  final SpeciesCacheDb cacheDb;
  final bool _useMockData;
  final Future<String?> Function(Uint8List) _sendFrameFn;

  /// Attempts to identify a fish species from [frameBytes] using the
  /// iNaturalist Computer Vision API.
  ///
  /// Returns a [DetectionResult] on success, or `null` when:
  /// - the user has not granted cloud fallback consent, or
  /// - mock mode is disabled and the HTTP call fails or times out, or
  /// - the API response contains no usable taxon suggestion.
  Future<DetectionResult?> identify(
    Uint8List frameBytes,
    BuildContext context,
  ) async {
    final granted = await consentService.requestConsentIfNeeded(context);
    if (!granted) return null;

    if (_useMockData) return _mockResult();

    return _fetchFromInat(frameBytes);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Returns a hardcoded [DetectionResult] for [_kMockScientificName].
  Future<DetectionResult?> _mockResult() async {
    const speciesInfo = SpeciesInfo(
      scientificName: _kMockScientificName,
      rating: SeafoodWatchRating.notRated,
      commonNames: {'en': _kMockCommonName},
    );
    await cacheDb.store(speciesInfo);
    return const DetectionResult(
      scientificName: _kMockScientificName,
      confidence: 1.0,
      boundingBox: Rect.zero,
      speciesInfo: speciesInfo,
    );
  }

  /// Calls [_sendFrameFn] and parses the response.
  ///
  /// Returns `null` if [_sendFrameFn] returns null (it handles its own
  /// error logging) or if the response cannot be parsed.
  Future<DetectionResult?> _fetchFromInat(Uint8List frameBytes) async {
    try {
      final body = await _sendFrameFn(frameBytes);
      if (body == null) return null;
      return _parseResponse(body);
    } on TimeoutException catch (e) {
      debugPrint('CloudFallbackService: request timed out — $e');
      return null;
    } on Exception catch (e) {
      debugPrint('CloudFallbackService: request failed — $e');
      return null;
    }
  }

  /// Parses the iNaturalist Computer Vision response body.
  ///
  /// Extracts the top suggestion's [taxon.name] (scientific name) and [score]
  /// (confidence), stores the result in [cacheDb], and wraps it in a
  /// [DetectionResult].
  Future<DetectionResult?> _parseResponse(String body) async {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final results = decoded['results'] as List<dynamic>?;

      if (results == null || results.isEmpty) {
        debugPrint('CloudFallbackService: no results in iNaturalist response');
        return null;
      }

      final top = results.first as Map<String, dynamic>;
      final taxon = top['taxon'] as Map<String, dynamic>?;
      final score = (top['score'] as num?)?.toDouble();

      if (taxon == null || score == null) {
        debugPrint('CloudFallbackService: missing taxon or score in response');
        return null;
      }

      final scientificName = taxon['name'] as String?;
      if (scientificName == null || scientificName.isEmpty) {
        debugPrint('CloudFallbackService: empty scientific name in response');
        return null;
      }

      final speciesInfo = SpeciesInfo(
        scientificName: scientificName,
        rating: SeafoodWatchRating.notRated,
        commonNames: const {},
      );

      await cacheDb.store(speciesInfo);

      return DetectionResult(
        scientificName: scientificName,
        confidence: score,
        boundingBox: Rect.zero,
        speciesInfo: speciesInfo,
      );
    } on Exception catch (e) {
      debugPrint('CloudFallbackService: failed to parse response — $e');
      return null;
    }
  }
}