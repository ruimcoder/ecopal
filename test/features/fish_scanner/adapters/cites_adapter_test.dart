import 'package:ecopal/features/fish_scanner/adapters/cites_adapter.dart';
import 'package:ecopal/features/fish_scanner/data/species_cache_db.dart';
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

  // ---------------------------------------------------------------------------
  // Mock data correctness
  // ---------------------------------------------------------------------------

  group('CitesAdapter mock mode', () {
    late CitesAdapter adapter;

    setUp(() {
      adapter = CitesAdapter(useMockData: true);
    });

    test('European eel returns Appendix II', () async {
      final appendix = await adapter.getAppendix('Anguilla anguilla');
      expect(appendix, equals(CitesAppendix.appendixII));
    });

    test('Largetooth sawfish returns Appendix I', () async {
      final appendix = await adapter.getAppendix('Pristis pristis');
      expect(appendix, equals(CitesAppendix.appendixI));
    });

    test('Atlantic Bluefin tuna returns notListed', () async {
      final appendix = await adapter.getAppendix('Thunnus thynnus');
      expect(appendix, equals(CitesAppendix.notListed));
    });

    test('Whale shark returns Appendix II', () async {
      final appendix = await adapter.getAppendix('Rhincodon typus');
      expect(appendix, equals(CitesAppendix.appendixII));
    });

    test('Great white shark returns Appendix II', () async {
      final appendix = await adapter.getAppendix('Carcharodon carcharias');
      expect(appendix, equals(CitesAppendix.appendixII));
    });

    test('unknown species returns notListed', () async {
      final appendix = await adapter.getAppendix('Fictus imaginarius');
      expect(appendix, equals(CitesAppendix.notListed));
    });

    test('result is cached on second call', () async {
      // First call populates cache.
      await adapter.getAppendix('Anguilla anguilla');

      // Verify the cache row exists.
      final db = SpeciesCacheDb.instance.rawDatabase;
      final rows = await db.query(
        'cites_cache',
        where: 'scientific_name = ?',
        whereArgs: ['Anguilla anguilla'],
      );
      expect(rows, hasLength(1));
      expect(rows.first['appendix'], equals('appendixII'));
    });
  });

  // ---------------------------------------------------------------------------
  // CitesAppendix enum i18n keys
  // ---------------------------------------------------------------------------

  group('CitesAppendix i18n keys', () {
    test('appendixI maps to citesBadgeAppendixI', () {
      expect(CitesAppendix.appendixI.i18nKey, equals('citesBadgeAppendixI'));
    });

    test('appendixII maps to citesBadgeAppendixII', () {
      expect(CitesAppendix.appendixII.i18nKey, equals('citesBadgeAppendixII'));
    });

    test('appendixIII maps to citesBadgeAppendixIII', () {
      expect(
        CitesAppendix.appendixIII.i18nKey,
        equals('citesBadgeAppendixIII'),
      );
    });

    test('notListed maps to citesBadgeNotListed', () {
      expect(CitesAppendix.notListed.i18nKey, equals('citesBadgeNotListed'));
    });
  });
}
