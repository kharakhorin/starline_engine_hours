// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:starline_engine_hours/utils/engine_hours_calculator.dart';
import 'package:starline_engine_hours/utils/strarline_client.dart';

void main() {
  // Ручной тест: обращается к реальному API StarLine с реальными
  // логином/паролем. Запускать локально, заменив креды:
  // flutter test --plain-name StarlineClient
  test('StarlineClient', () async {
    const login = '';
    const pass = '';
    if (login.isEmpty) {
      print('Пропущено: укажите логин/пароль для ручного запуска');
      return;
    }
    var client = StarlineClient();
    await client.login(login, pass);
    var resultDevice = await client.getHistory(DateTime(2021, 12, 25));
    print(resultDevice.data);
    EngineHoursCalculator(resultDevice.data);
  }, skip: true);

  test('EngineHoursCalculator parses sessions from raw history', () {
    var calc = EngineHoursCalculator(
        json.decode(File('test/rawHistory.json').readAsStringSync()));
    expect(calc.engineSessions, isNotEmpty);
    expect(calc.totalHours, greaterThanOrEqualTo(Duration.zero));
    for (var element in calc.engineSessions) {
      expect(
          element.end.isAfter(element.start) ||
              element.end.isAtSameMomentAs(element.start),
          isTrue,
          reason:
              'сессия заканчивается раньше, чем начинается: ${element.start}');
    }
  });
}
