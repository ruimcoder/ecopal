import 'package:ecopal/features/fish_scanner/data/species_cache_db.dart';
import 'package:ecopal/features/fish_scanner/models/detection_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  const tuna = SpeciesInfo(
    scientificName: 'Thunnus thynnus',
    rating: SeafoodWatchRating.avoid,
    commonNames: {'en': 'Atlantic Bluefin Tuna', 'pt': 'Atum-rabilho'},
    fishbaseCode: 143,
  );

  group('store → lookup', () {
    test('returns stored species on cache hit', () async {
      await SpeciesCacheDb.instance.store(tuna);

      final result = await SpeciesCacheDb.instance.lookup(
        'Thunnus thynnus',
        'en',
      );

      expect(result, isNotNull);
      expect(result!.scientificName, equals('Thunnus thynnus'));
      expect(result.rating, equals(SeafoodWatchRating.avoid));
      expect(result.fishbaseCode, equals(143));
      expect(result.commonNames['en'], equals('Atlantic Bluefin Tuna'));
      expect(result.commonNames['pt'], equals('Atum-rabilho'));
    });

    test('returns null on cache miss', () async {
      final result = await SpeciesCacheDb.instance.lookup(
        'Unknown species',
        'en',
      );

      expect(result, isNull);
    });
  });

  group('TTL expiry', () {
    test('returns null when entry is expired', () async {
      await SpeciesCacheDb.instance.storeWithTimestamps(
        tuna,
        fetchedAt: 1,
        expiresAt: 1, // epoch second 1 — always in the past
      );

      final result = await SpeciesCacheDb.instance.lookup(
        'Thunnus thynnus',
        'en',
      );

      expect(result, isNull);
    });
  });

  group('clearExpired', () {
    test('removes expired rows but keeps valid ones', () async {
      const salmon = SpeciesInfo(
        scientificName: 'Salmo salar',
        rating: SeafoodWatchRating.bestChoice,
        commonNames: {'en': 'Atlantic Salmon'},
      );

      // tuna is expired, salmon is fresh
      await SpeciesCacheDb.instance.storeWithTimestamps(
        tuna,
        fetchedAt: 1,
        expiresAt: 1,
      );
      await SpeciesCacheDb.instance.store(salmon);

      await SpeciesCacheDb.instance.clearExpired();

      final expiredResult = await SpeciesCacheDb.instance.lookup(
        'Thunnus thynnus',
        'en',
      );
      final validResult = await SpeciesCacheDb.instance.lookup(
        'Salmo salar',
        'en',
      );

      expect(expiredResult, isNull);
      expect(validResult, isNotNull);
      expect(validResult!.rating, equals(SeafoodWatchRating.bestChoice));
    });
  });
}
