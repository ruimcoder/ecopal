import 'dart:io';

import 'package:ecopal/features/fish_scanner/adapters/seafood_watch_adapter.dart';
import 'package:ecopal/features/fish_scanner/data/species_cache_db.dart';
import 'package:ecopal/features/fish_scanner/models/detection_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fake [http.Client] that throws a [SocketException] on every request.
///
/// Injected in tests that verify network-failure fallback behaviour or
/// that the HTTP client is never reached (cache-first / mock mode).
class _ThrowingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw const SocketException('Network unavailable');
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await SpeciesCacheDb.instance.init(dbPath: inMemoryDatabasePath);
  });

  tearDown(() async {
    await SpeciesCacheDb.instance.close();
  });

  group('mock mode', () {
    test('returns correct rating for a known Best Choice species', () async {
      final adapter = SeafoodWatchAdapter(useMockData: true);

      expect(
        await adapter.getRating('Oncorhynchus mykiss'),
        SeafoodWatchRating.bestChoice,
      );
    });

    test('returns correct rating for a known Avoid species', () async {
      final adapter = SeafoodWatchAdapter(useMockData: true);

      expect(
        await adapter.getRating('Thunnus thynnus'),
        SeafoodWatchRating.avoid,
      );
    });

    test('unknown species returns notRated', () async {
      final adapter = SeafoodWatchAdapter(useMockData: true);

      expect(
        await adapter.getRating('Fictus specius unknownus'),
        SeafoodWatchRating.notRated,
      );
    });
  });

  group('cache-first behaviour', () {
    test(
        'cache hit returns the cached rating and does not call mock or API',
        () async {
      // Pre-populate the cache with a rating that differs from mock data.
      // Mock data has Oncorhynchus mykiss → bestChoice.
      await SpeciesCacheDb.instance.store(
        const SpeciesInfo(
          scientificName: 'Oncorhynchus mykiss',
          rating: SeafoodWatchRating.avoid, // deliberately different
          commonNames: {},
        ),
      );

      // Use a throwing HTTP client to prove the network is never reached.
      final adapter = SeafoodWatchAdapter(
        useMockData: true,
        httpClient: _ThrowingClient(),
      );

      final rating = await adapter.getRating('Oncorhynchus mykiss');

      // Must come from cache (avoid), not from mock data (bestChoice).
      expect(rating, SeafoodWatchRating.avoid);
    });

    test('cache hit in live mode also skips the API call', () async {
      await SpeciesCacheDb.instance.store(
        const SpeciesInfo(
          scientificName: 'Gadus morhua',
          rating: SeafoodWatchRating.goodAlternative,
          commonNames: {},
        ),
      );

      final adapter = SeafoodWatchAdapter(
        useMockData: false,
        httpClient: _ThrowingClient(), // would throw if called
      );

      // Should return the cached value without triggering the throwing client.
      expect(
        await adapter.getRating('Gadus morhua'),
        SeafoodWatchRating.goodAlternative,
      );
    });
  });

  group('network failure handling', () {
    test(
        'live mode with no cache and network failure returns notRated',
        () async {
      final adapter = SeafoodWatchAdapter(
        useMockData: false,
        httpClient: _ThrowingClient(),
      );

      expect(
        await adapter.getRating('Thunnus thynnus'),
        SeafoodWatchRating.notRated,
      );
    });

    test(
        'live mode with fresh cache and network failure returns cached rating',
        () async {
      await SpeciesCacheDb.instance.store(
        const SpeciesInfo(
          scientificName: 'Sardina pilchardus',
          rating: SeafoodWatchRating.bestChoice,
          commonNames: {},
        ),
      );

      final adapter = SeafoodWatchAdapter(
        useMockData: false,
        httpClient: _ThrowingClient(),
      );

      // Cache is fresh → returns cached rating before any network attempt.
      expect(
        await adapter.getRating('Sardina pilchardus'),
        SeafoodWatchRating.bestChoice,
      );
    });
  });
}
