import 'dart:convert';
import 'package:flutter/services.dart';

enum RegionalStatus { osparThreatened, helcomRedListed, notListed }

class RegionalAdapter {
  final _ospar = <String>{};
  final _helcom = <String>{};

  Future<void> init() async {
    final osparJson = await rootBundle.loadString('assets/data/ospar_species.json');
    final helcomJson = await rootBundle.loadString('assets/data/helcom_species.json');

    for (final entry in jsonDecode(osparJson) as List<dynamic>) {
      _ospar.add((entry['scientific_name'] as String).toLowerCase());
    }
    for (final entry in jsonDecode(helcomJson) as List<dynamic>) {
      _helcom.add((entry['scientific_name'] as String).toLowerCase());
    }
  }

  RegionalStatus getStatus(String scientificName) {
    final name = scientificName.toLowerCase();
    if (_ospar.contains(name)) return RegionalStatus.osparThreatened;
    if (_helcom.contains(name)) return RegionalStatus.helcomRedListed;
    return RegionalStatus.notListed;
  }
}
