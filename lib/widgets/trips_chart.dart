import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:starline_engine_hours/utils/engine_hours_calculator.dart';

/// Мини-график «длительность по дням»: колонки — учтённые часы за день.
/// Без внешних пакетов: обычные контейнеры в горизонтальной прокрутке
/// (свежие дни — справа). Слева — ось длительности, снизу — разреженные
/// подписи дат: на коротком периоде по неделям («05.10»), на длинном
/// по месяцам («май»). Возможность прокрутки подсказывает затухание
/// колонок у края; точная дата — долгим нажатием.
class TripsChart extends StatefulWidget {
  final List<EngineSession> sessions;

  const TripsChart({super.key, required this.sessions});

  @override
  State<TripsChart> createState() => _TripsChartState();
}

class _TripsChartState extends State<TripsChart> {
  static final DateFormat _dayFormatter = DateFormat('dd.MM');

  static const _monthsShort = [
    'янв', 'фев', 'мар', 'апр', 'май', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];

  final ScrollController _scrollController = ScrollController();

  /// Есть ли скрытые колонки за левым/правым краем прокрутки.
  bool _fadeLeft = false;
  bool _fadeRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateFades);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFades());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _updateFades() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Режим reverse: offset 0 — виден правый (свежий) край истории,
    // за левым краем скрыты старые дни.
    final fadeLeft = position.pixels < position.maxScrollExtent - 0.5;
    final fadeRight = position.pixels > 0.5;
    if (fadeLeft != _fadeLeft || fadeRight != _fadeRight) {
      setState(() {
        _fadeLeft = fadeLeft;
        _fadeRight = fadeRight;
      });
    }
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return hours > 0 ? '$hoursч $minsм' : '$minsм';
  }

  String _hoursLabel(double hours) =>
      hours == hours.roundToDouble()
          ? '${hours.round()}ч'
          : '${hours.toStringAsFixed(1).replaceAll('.', ',')}ч';

  DateTime _weekStart(DateTime date) =>
      DateTime(date.year, date.month, date.day)
          .subtract(Duration(days: date.weekday - 1));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Сумма учтённых минут по дням.
    final perDay = <DateTime, int>{};
    for (final session in widget.sessions) {
      if (session.status != SessionStatus.ok) continue;
      perDay[session.date] =
          (perDay[session.date] ?? 0) + session.duration.inMinutes;
    }
    perDay.removeWhere((_, minutes) => minutes <= 0);
    final days = perDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (days.isEmpty) return const SizedBox.shrink();

    // Шкала: округляем максимум вверх до целого часа.
    final scaleHours = (days
                .map((entry) => entry.value)
                .reduce((a, b) => a > b ? a : b) /
            60)
        .ceil()
        .clamp(1, 100000);
    final scaleMinutes = scaleHours * 60;

    const barWidth = 10.0;
    const barGap = 4.0;
    const columnWidth = barWidth + barGap;
    const chartHeight = 110.0;
    const labelStripHeight = 18.0;
    const labelWidth = 34.0;
    // Запас справа, чтобы подпись последней колонки не резалась.
    final contentWidth = days.length * columnWidth + labelWidth;
    final labelStyle =
        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);

    // Разреженные подписи оси X: под первой колонкой недели на периоде
    // до двух месяцев, дальше — под первой колонкой месяца.
    final byWeek = days.last.key.difference(days.first.key).inDays <= 60;
    final labels = <({double left, String text})>[];
    for (var i = 0; i < days.length; i++) {
      final date = days[i].key;
      final prev = i > 0 ? days[i - 1].key : null;
      final newGroup = prev == null ||
          (byWeek
              ? _weekStart(date) != _weekStart(prev)
              : date.month != prev.month || date.year != prev.year);
      if (!newGroup) continue;
      final text =
          byWeek ? _dayFormatter.format(date) : _monthsShort[date.month - 1];
      final left = i * columnWidth + barWidth / 2 - labelWidth / 2;
      // На разреженной истории не даём подписям слипаться.
      if (labels.isNotEmpty && left - labels.last.left < labelWidth) {
        continue;
      }
      labels.add((left: left, text: text));
    }

    Widget scroll = SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      reverse: true, // показываем свежие дни
      child: SizedBox(
        height: chartHeight + labelStripHeight,
        width: contentWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: chartHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in days)
                    Padding(
                      padding: const EdgeInsets.only(right: barGap),
                      child: Tooltip(
                        message:
                            '${_dayFormatter.format(day.key)} — ${_formatDuration(day.value)}',
                        child: Container(
                          width: barWidth,
                          height: (day.value / scaleMinutes * chartHeight)
                              .clamp(3.0, chartHeight),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: labelStripHeight,
              child: Stack(
                children: [
                  for (final label in labels)
                    Positioned(
                      left: label.left
                          .clamp(0.0, contentWidth - labelWidth)
                          .toDouble(),
                      width: labelWidth,
                      child: Text(
                        label.text,
                        textAlign: TextAlign.center,
                        style: labelStyle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // Затухание у края подсказывает, что за ним скрыты ещё колонки.
    if (_fadeLeft || _fadeRight) {
      const fade = 0.10;
      final gradient = LinearGradient(
        colors: [
          if (_fadeLeft) Colors.transparent,
          Colors.black,
          Colors.black,
          if (_fadeRight) Colors.transparent,
        ],
        stops: [
          if (_fadeLeft) 0.0,
          _fadeLeft ? fade : 0.0,
          _fadeRight ? 1 - fade : 1.0,
          if (_fadeRight) 1.0,
        ],
      );
      scroll = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => gradient.createShader(bounds),
        child: scroll,
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Длительность по дням',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Подписи оси Y: максимум, середина, ноль.
                SizedBox(
                  width: 34,
                  height: chartHeight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_hoursLabel(scaleHours.toDouble()),
                          style: labelStyle),
                      Text(_hoursLabel(scaleHours / 2), style: labelStyle),
                      Text('0', style: labelStyle),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: chartHeight + labelStripHeight,
                    child: Stack(
                      children: [
                        // Лёгкая сетка: линия сверху и посередине.
                        for (final fraction in const [1.0, 0.5])
                          Positioned(
                            left: 0,
                            right: 0,
                            top: (1 - fraction) * chartHeight,
                            child: Container(
                                height: 1, color: scheme.outlineVariant),
                          ),
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: scroll,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
