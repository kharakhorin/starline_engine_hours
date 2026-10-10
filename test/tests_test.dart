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
    var devices = await client.getDevices();
    print('Устройства: '
        '${devices.map((d) => '${d.displayName} (${d.deviceId})').join(', ')}');
    var resultDevice =
        await client.getHistory(DateTime(2021, 12, 25), devices.first.deviceId);
    EngineHoursCalculator(resultDevice.data);
  }, skip: true);

  test('StarlineClient.parseDevices parses device list', () {
    var devices = StarlineClient.parseDevices({
      'answer': {
        'devices': [
          {'alias': 'Старое авто', 'device_id': 1111111, 'status': 0},
          {'alias': 'Моё авто', 'device_id': 222222222222222, 'status': 1},
          {
            'device_id': 777,
          },
        ],
      }
    });
    // Офлайн-устройства не отбрасываются (status == 0 — просто не в сети),
    // но сортируются в конец списка.
    expect(devices.length, 3);
    expect(devices[0].deviceId, '222222222222222');
    expect(devices[0].displayName, 'Моё авто');
    expect(devices[0].isOnline, isTrue);
    expect(devices[1].displayName, 'Старое авто');
    expect(devices[1].isOnline, isFalse);
    expect(devices[2].displayName, 'Устройство 777');
    expect(devices[2].isOnline, isFalse); // статус не указан — офлайн
  });

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

  // Синтетическое событие движка (порядок как в API — от новых к старым).
  Map<String, dynamic> engineEvent(int eventId, DateTime time) => {
        'event_id': eventId,
        'group_id': 1,
        'ts': time.millisecondsSinceEpoch ~/ 1000,
      };
  const startId = 1037;
  const stopId = 1042;

  test('EngineHoursCalculator counts clean start/stop pairs', () {
    var day = DateTime(2026, 1, 10);
    var calc = EngineHoursCalculator([
      engineEvent(stopId, day.add(const Duration(hours: 16))),
      engineEvent(startId, day.add(const Duration(hours: 15))),
      engineEvent(stopId, day.add(const Duration(hours: 11))),
      engineEvent(startId, day.add(const Duration(hours: 10))),
    ]);
    expect(calc.engineSessions.length, 2);
    expect(calc.totalHours, const Duration(hours: 2));
    expect(calc.engineSessions.every((s) => s.status == SessionStatus.ok),
        isTrue);
  });

  test('EngineHoursCalculator drops session with lost stop event', () {
    // Стоп первой сессии не записан: за стартом идёт следующий старт.
    var day = DateTime(2026, 1, 10);
    var calc = EngineHoursCalculator([
      engineEvent(stopId, day.add(const Duration(hours: 16))),
      engineEvent(startId, day.add(const Duration(hours: 15))),
      engineEvent(stopId, day.add(const Duration(hours: 13))),
      engineEvent(startId, day.add(const Duration(hours: 12))),
      engineEvent(startId, day.add(const Duration(hours: 10))),
    ]);
    expect(calc.engineSessions.length, 3);
    // Битая сессия 10:00→12:00 помечена, но в сумму не идёт.
    expect(calc.engineSessions[0].status, SessionStatus.noStop);
    expect(calc.engineSessions[0].duration, const Duration(hours: 2));
    expect(calc.totalHours, const Duration(hours: 2));
  });

  test('EngineHoursCalculator skips dangling stop with lost start', () {
    // Старт второй сессии не записан: за стопом идёт следующий стоп.
    var day = DateTime(2026, 1, 10);
    var calc = EngineHoursCalculator([
      engineEvent(stopId, day.add(const Duration(hours: 16))),
      engineEvent(startId, day.add(const Duration(hours: 15))),
      engineEvent(stopId, day.add(const Duration(hours: 13))),
      engineEvent(stopId, day.add(const Duration(hours: 11))),
      engineEvent(startId, day.add(const Duration(hours: 10))),
    ]);
    expect(calc.engineSessions.length, 2);
    expect(calc.totalHours, const Duration(hours: 2));
    expect(calc.engineSessions.every((s) => s.status == SessionStatus.ok),
        isTrue);
  });

  test('EngineHoursCalculator marks session exceeding the threshold', () {
    var day = DateTime(2026, 1, 10);
    var raw = [
      engineEvent(stopId, day.add(const Duration(hours: 20))),
      engineEvent(startId, day.add(const Duration(hours: 10))),
    ];
    // 10-часовая сессия: при пороге 8 ч — исключена, при 12 ч — учтена.
    expect(
        EngineHoursCalculator(raw).totalHours, Duration.zero);
    expect(EngineHoursCalculator(raw, maxSession: const Duration(hours: 12))
        .totalHours, const Duration(hours: 10));
    expect(EngineHoursCalculator(raw).engineSessions.single.status,
        SessionStatus.tooLong);
  });

  test('EngineHoursCalculator marks trailing start without stop', () {
    var day = DateTime(2026, 1, 10);
    var calc = EngineHoursCalculator([
      engineEvent(startId, day.add(const Duration(hours: 15))),
      engineEvent(stopId, day.add(const Duration(hours: 11))),
      engineEvent(startId, day.add(const Duration(hours: 10))),
    ]);
    expect(calc.engineSessions.length, 2);
    expect(calc.engineSessions[1].status, SessionStatus.open);
    expect(calc.totalHours, const Duration(hours: 1));
  });

  test('EngineHoursCalculator skips leading stop before window', () {
    var day = DateTime(2026, 1, 10);
    var calc = EngineHoursCalculator([
      engineEvent(stopId, day.add(const Duration(hours: 11))),
      engineEvent(startId, day.add(const Duration(hours: 10))),
      engineEvent(stopId, day.add(const Duration(days: -1, hours: 23))),
    ]);
    expect(calc.engineSessions.length, 1);
    expect(calc.totalHours, const Duration(hours: 1));
  });
}
