import 'package:flutter/material.dart';
import 'package:starline_engine_hours/utils/engine_hours_calculator.dart';
import 'package:intl/intl.dart';

/// Карточка одного дня: заголовок с датой и учтёнными часами,
/// внутри — список сессий. Исключённые фильтром сессии — серым
/// с причиной справа.
class EngineSessionsRow extends StatelessWidget {
  final List<EngineSession> engineSessions;
  const EngineSessionsRow(this.engineSessions, {super.key});

  static final DateFormat _dateFormatter = DateFormat('dd.MM.yyyy');
  static final DateFormat _hoursFormatter = DateFormat('HH:mm');

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '$hoursч $minutesм';
    // Сессии короче минуты показываем в секундах — иначе реальный
    // короткий запуск выглядит фантомом «0м».
    return minutes > 0 ? '$minutesм' : '${duration.inSeconds}с';
  }

  /// Почему сессия не попала в сумму моточасов.
  String? _exclusionReason(EngineSession session) {
    switch (session.status) {
      case SessionStatus.noStop:
      case SessionStatus.open:
        return 'стоп не записан';
      case SessionStatus.tooLong:
        return 'слишком длинная';
      case SessionStatus.ok:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    var dayDuration = const Duration();
    for (final session in engineSessions) {
      if (session.status == SessionStatus.ok) {
        dayDuration += session.duration;
      }
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: ExpansionTile(
        // Явная форма без рамки: дефолтная M3-рамка ExpansionTile
        // рисует тёмные линии сверху и снизу развёрнутой карточки.
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12))),
        collapsedShape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12))),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _dateFormatter.format(engineSessions[0].date),
                style: textTheme.titleMedium,
              ),
            ),
            Text(
              _formatDuration(dayDuration),
              style: textTheme.titleMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        children: [
          for (final session in engineSessions)
            _buildSessionRow(context, session),
        ],
      ),
    );
  }

  Widget _buildSessionRow(BuildContext context, EngineSession session) {
    final scheme = Theme.of(context).colorScheme;
    final reason = _exclusionReason(session);
    return ListTile(
      dense: true,
      leading: Icon(
        Icons.timer,
        color: reason != null ? scheme.outline : scheme.primary,
      ),
      title: Text(
        '${_hoursFormatter.format(session.start)} – ${_hoursFormatter.format(session.end)}',
        style: reason != null
            ? TextStyle(color: scheme.outline)
            : null,
      ),
      trailing: Text(
        reason ?? _formatDuration(session.duration),
        style: TextStyle(
          color: reason != null ? scheme.outline : scheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
  }
}
