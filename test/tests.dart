// ignore_for_file: unused_local_variable, avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:starline_engine_hours/utils/engine_hours_calculator.dart';
import 'package:starline_engine_hours/utils/strarline_client.dart';

void main() {
  test('StarlineClient', () async {
    var client = StarlineClient();
    var result = await client.login("", "");
    var resultDevice = await client.getHistory(DateTime(2021, 12, 25));
    print(resultDevice.data);
    EngineHoursCalculator(resultDevice.data);
  });
  test('EngineHoursCalculator', () {
    EngineHoursCalculator(File('test/rawHistory.json').readAsStringSync());
  });
}
