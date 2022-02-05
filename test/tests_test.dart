// ignore_for_file: unused_local_variable, avoid_print, avoid_function_literals_in_foreach_calls, prefer_const_constructors

import 'dart:convert';
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
    var calc = EngineHoursCalculator(
        json.decode(File('test/rawHistory.json').readAsStringSync()));
    calc.engineSessions.forEach((element) {
      if (element.duration > Duration(hours: 1)) {
        print(element.start.toString() + ' ' + element.duration.toString());
      }
    });
  });
}
