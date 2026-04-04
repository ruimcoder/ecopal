import 'package:ecopal/features/fish_scanner/adapters/fishbase_adapter.dart';
import 'package:ecopal/features/fish_scanner/data/species_cache_db.dart';
import 'package:ecopal/features/fish_scanner/models/detection_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fishbase_adapter_test.mocks.dart';

@GenerateMocks([http.Client])
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

  group('FishBaseAdapter', () {
    test('cache hit returns names without API call', () async {
      final mockClient = MockClient();

      const species = SpeciesInfo(
        scientificName: 'Thunnus thynnus',
        rating: SeafoodWatchRating.notRated,
        commonNames: {'en': 'Atlantic Bluefin Tuna', 'pt': 'Atum-rabilho'},
        fishbaseCode: 143,
      );
      await SpeciesCacheDb.instance.store(species);

      final adapter = FishBaseAdapter(
        client: mockClient,
        rateLimitInterval: Duration.zero,
      );

      final result = await adapter.getCommonNames('Thunnus thynnus');

      expect(result['en'], equals('Atlantic Bluefin Tuna'));
      expect(result['pt'], equals('Atum-rabilho'));
      verifyNever(mockClient.get(any));
    });

    test('cache miss fetches from API and stores in cache', () async {
      final mockClient = MockClient();

      when(mockClient.get(any)).thenAnswer((call) async {
        final uri = call.positionalArguments[0] as Uri;
        if (uri.path.contains('/species')) {
          return http.Response(
            '{"data": [{"SpecCode": 143, "Genus": "Thunnus", "Species": "thynnus"}]}',
            200,
          );
        }
        return http.Response(
          '{"data": ['
          '{"ComName": "Atlantic Bluefin Tuna", "Language": "English", "SpecCode": 143},'
          '{"ComName": "Atum-rabilho", "Language": "Portuguese", "SpecCode": 143}'
          ']}',
          200,
        );
      });

      final adapter = FishBaseAdapter(
        client: mockClient,
        rateLimitInterval: Duration.zero,
      );

      final result = await adapter.getCommonNames('Thunnus thynnus');

      expect(result['en'], equals('Atlantic Bluefin Tuna'));
      expect(result['pt'], equals('Atum-rabilho'));

      final cached =
          await SpeciesCacheDb.instance.lookup('Thunnus thynnus', 'en');
      expect(cached, isNotNull);
      expect(cached!.commonNames['en'], equals('Atlantic Bluefin Tuna'));
      expect(cached.fishbaseCode, equals(143));
    });

    test('API failure returns scientific name fallback', () async {
      final mockClient = MockClient();

      when(mockClient.get(any)).thenAnswer(
        (_) async => http.Response('Internal Server Error', 500),
      );

      final adapter = FishBaseAdapter(
        client: mockClient,
        rateLimitInterval: Duration.zero,
      );

      final result = await adapter.getCommonNames('Thunnus thynnus');

      expect(result, equals({'en': 'Thunnus thynnus'}));
    });

    test('getCommonNames parses JSON response correctly', () async {
      final mockClient = MockClient();

      when(mockClient.get(any)).thenAnswer((call) async {
        final uri = call.positionalArguments[0] as Uri;
        if (uri.queryParameters.containsKey('Genus')) {
          return http.Response('{"data": [{"SpecCode": 999}]}', 200);
        }
        return http.Response(
          '{"data": ['
          '{"ComName": "Cod", "Language": "English", "SpecCode": 999},'
          '{"ComName": "Kabeljau", "Language": "German", "SpecCode": 999},'
          '{"ComName": "Morue", "Language": "French", "SpecCode": 999}'
          ']}',
          200,
        );
      });

      final adapter = FishBaseAdapter(
        client: mockClient,
        rateLimitInterval: Duration.zero,
      );

      final result = await adapter.getCommonNames('Gadus morhua');

      expect(result['en'], equals('Cod'));
      expect(result['de'], equals('Kabeljau'));
      expect(result['fr'], equals('Morue'));
    });
  });
}