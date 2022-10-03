// ignore: implementation_imports
import 'package:collection/src/iterable_extensions.dart';

class EngineHoursCalculator {
  Duration totalHours = const Duration();
  List<EngineSession> engineSessions = <EngineSession>[];
  List<List<EngineSession>> engineSessionsByDate = <List<EngineSession>>[];
  List<int> startCommands = [1037, 20532, 601, 605];
  List<int> stopCommands = [1042, 602];

  EngineHoursCalculator(dynamic rawData) {
    if (rawData.length < 2) return;

    List<StarlineEvent> allEvents = rawData
        .map<StarlineEvent>((json) => StarlineEvent.fromJson(json))
        .toList();

    var engineEvents = allEvents
        .where((e) =>
            startCommands.contains(e.eventId) ||
            stopCommands.contains(e.eventId))
        .toList()
        .reversed
        .toList();

    if (engineEvents.length < 2) return;

    if (stopCommands.contains(engineEvents[0].eventId)) {
      engineEvents.removeAt(0);
    }

    for (int i = 0; i < engineEvents.length - 1; i += 2) {
      if (stopCommands.contains(engineEvents[i].eventId)) {
        i -= 1;
        continue;
      }
      engineSessions.add(EngineSession(
          engineEvents[i].eventTime, engineEvents[i + 1].eventTime));
      totalHours += engineSessions.last.duration;
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

  EngineSession(this.start, this.end) {
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
