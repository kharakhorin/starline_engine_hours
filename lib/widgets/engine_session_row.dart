import 'package:flutter/material.dart';
import 'package:starline_engine_hours/utils/engine_hours_calculator.dart';
import 'package:intl/intl.dart';

class EngineSessionsRow extends StatelessWidget {
  final List<EngineSession> engineSessions;
  final DateFormat dateFormatter = DateFormat('dd.MM.yyyy');
  final DateFormat hoursFormatter = DateFormat('HH:mm');
  EngineSessionsRow(this.engineSessions, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: sessionsList(),
    );
  }

  ExpansionTile sessionsList() {
    var list = <Widget>[];
    var dayDuration = const Duration();
    for (var session in engineSessions) {
      list.add(Padding(
          padding: const EdgeInsets.only(
            left: 16.0,
          ),
          child: ListTile(
              title: Row(children: [
            Icon(
              Icons.timer,
              color: Colors.blue[500],
            ),
            Padding(
                padding: const EdgeInsets.only(
                  left: 10.0,
                ),
                child: Text(hoursFormatter.format(session.start) +
                    ' - ' +
                    hoursFormatter.format(session.end)))
          ]))));
      dayDuration += session.end.difference(session.start);
    }
    return ExpansionTile(
        title: ListTile(
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              dateFormatter.format(engineSessions[0].date),
            ),
            //Text(dayDuration.inHours.toString() + ' ч')
            Text(
                "${dayDuration.inHours}ч ${dayDuration.inMinutes.remainder(60)}мин")
          ]),
          leading: Icon(
            Icons.date_range,
            color: Colors.blue[500],
          ),
        ),
        children: list);
  }
}
