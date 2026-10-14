import 'package:collection/collection.dart';

/// Статус сессии: попадает ли она в сумму моточасов.
enum SessionStatus {
  /// Обычная сессия «старт → стоп».
  ok,

  /// Стоп не записан (например, не было сети в момент остановки):
  /// сессия фактически длится до следующего старта и в сумму не идёт.
  noStop,

  /// Длительность больше настроенного порога — в сумму не идёт.
  tooLong,

  /// Старт в конце истории, стопа после него ещё нет.
  open,
}

class EngineHoursCalculator {
  Duration totalHours = const Duration();
  List<EngineSession> engineSessions = <EngineSession>[];
  List<List<EngineSession>> engineSessionsByDate = <List<EngineSession>>[];
  List<int> startCommands = [1037, 20532, 601];
  List<int> stopCommands = [1042, 602];

  /// Порог «правдоподобности» сессии. Всё, что длится дольше,
  /// помечается [SessionStatus.tooLong] и не учитывается в сумме.
  final Duration maxSessionDuration;

  EngineHoursCalculator(dynamic rawData, {Duration? maxSession})
      : maxSessionDuration = maxSession ?? const Duration(hours: 8) {
    if (rawData.length < 1) return;

    List<StarlineEvent> allEvents = rawData
        .map<StarlineEvent>((json) => StarlineEvent.fromJson(json))
        .toList();

    // API отдаёт события от новых к старым — разворачиваем в хронологию.
    var engineEvents = allEvents
        .where((e) =>
            startCommands.contains(e.eventId) ||
            stopCommands.contains(e.eventId))
        .toList()
        .reversed
        .toList();

    // Одно и то же событие иногда прилетает дважды (баг уже встречался
    // в 1.x): дубль ломает чередование старт/стоп и рождает фантомные
    // нулевые сессии — убираем до сборки.
    final seen = <String>{};
    engineEvents = engineEvents
        .where((e) =>
            seen.add('${e.eventId}#${e.eventTime.millisecondsSinceEpoch}'))
        .toList();

    if (engineEvents.isEmpty) return;

    // В чистом логе события движка строго чередуются: старт, стоп, старт…
    // Если за стартом идёт ещё один старт — стоп первого потерян,
    // если за стопом идёт ещё один стоп — потерян старт. Оба случая
    // означают, что реальная длительность сессии неизвестна.
    StarlineEvent? openStart;
    for (final event in engineEvents) {
      final isStart = startCommands.contains(event.eventId);
      if (isStart) {
        if (openStart != null) {
          engineSessions.add(EngineSession(
              openStart.eventTime, event.eventTime,
              status: SessionStatus.noStop));
        }
        openStart = event;
      } else {
        if (openStart == null) {
          // Стоп без парного старта: старт потерян или был до окна истории.
          continue;
        }
        // Старт и стоп в одну и ту же секунду — не сессия (двигатель
        // столько не работает): артефакт истории, в список не берём.
        if (openStart.eventTime != event.eventTime) {
          engineSessions
              .add(EngineSession(openStart.eventTime, event.eventTime));
        }
        openStart = null;
      }
    }
    if (openStart != null) {
      engineSessions.add(EngineSession(
          openStart.eventTime, openStart.eventTime,
          status: SessionStatus.open));
    }

    for (final session in engineSessions) {
      if (session.status == SessionStatus.ok &&
          session.duration > maxSessionDuration) {
        session.status = SessionStatus.tooLong;
      }
      if (session.status == SessionStatus.ok) {
        totalHours += session.duration;
      }
    }

    engineSessionsByDate = engineSessions
        .groupListsBy((element) => element.date)
        .values
        .toList()
        .reversed
        .toList();
  }
}

class EngineSession {
  late DateTime start;
  late DateTime end;
  late DateTime date;
  late Duration duration;
  SessionStatus status;

  EngineSession(this.start, this.end, {this.status = SessionStatus.ok}) {
    duration = end.difference(start);
    date = DateTime(start.year, start.month, start.day);
  }
}

class StarlineEvent {
  final int eventId;
  final int eventGroup;
  final DateTime eventTime;

  const StarlineEvent({
    required this.eventId,
    required this.eventGroup,
    required this.eventTime,
  });

  factory StarlineEvent.fromJson(Map<String, dynamic> json) {
    var ts1 = json['ts'] * Duration.millisecondsPerSecond;
    return StarlineEvent(
      eventId: json['event_id'] as int,
      eventGroup: json['group_id'] as int,
      eventTime: DateTime.fromMillisecondsSinceEpoch(ts1),
    );
  }
}
