import 'dart:convert';

import 'package:ecopal/features/fish_scanner/adapters/regional_adapter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final osparJson = jsonEncode([
    {'scientific_name': 'Gadus morhua', 'status': 'threatened', 'region': 'NE Atlantic'},
    {'scientific_name': 'Squalus acanthias', 'status': 'threatened', 'region': 'NE Atlantic'},
  ]);
  final helcomJson = jsonEncode([
    {'scientific_name': 'Salmo trutta', 'status': 'red_listed', 'region': 'Baltic Sea'},
    {'scientific_name': 'Gadus morhua', 'status': 'red_listed', 'region': 'Baltic Sea'},
  ]);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'assets/data/ospar_species.json') {
        return ByteData.sublistView(
          Uint8List.fromList(utf8.encode(osparJson)),
        );
      }
      if (key == 'assets/data/helcom_species.json') {
        return ByteData.sublistView(
          Uint8List.fromList(utf8.encode(helcomJson)),
        );
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  test('OSPAR species returns osparThreatened', () async {
    final adapter = RegionalAdapter();
    await adapter.init();
    expect(adapter.getStatus('Squalus acanthias'), RegionalStatus.osparThreatened);
  });

  test('HELCOM species returns helcomRedListed', () async {
    final adapter = RegionalAdapter();
    await adapter.init();
    expect(adapter.getStatus('Salmo trutta'), RegionalStatus.helcomRedListed);
  });

  test('Unknown species returns notListed', () async {
    final adapter = RegionalAdapter();
    await adapter.init();
    expect(adapter.getStatus('Unknown species'), RegionalStatus.notListed);
  });

  test('Species in both lists returns osparThreatened (OSPAR priority)', () async {
    final adapter = RegionalAdapter();
    await adapter.init();
    // Gadus morhua appears in both OSPAR and HELCOM lists; OSPAR takes priority
    expect(adapter.getStatus('Gadus morhua'), RegionalStatus.osparThreatened);
  });
}
