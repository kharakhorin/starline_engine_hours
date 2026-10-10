import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'utils/engine_hours_calculator.dart';
import 'utils/strarline_client.dart';
import 'widgets/engine_session_row.dart';
import 'widgets/trips_chart.dart';

/// Страница поддержки разработчика (CloudTips).
final Uri _donationUrl = Uri.parse('https://pay.cloudtips.ru/p/20f12342');

class ResultsPage extends StatefulWidget {
  final DateTime dateFrom;
  final String login;
  final String pass;

  const ResultsPage({
    super.key,
    required this.login,
    required this.pass,
    required this.dateFrom,
  });

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  final StarlineClient starlineClient = StarlineClient();
  List<StarlineDevice> devices = [];
  StarlineDevice? selectedDevice;
  EngineHoursCalculator? engineHours;
  String? error;
  bool isLoading = false;

  /// Сырой ответ истории — чтобы менять порог без нового запроса.
  dynamic lastRawHistory;
  int maxSessionHours = 8;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      await starlineClient.login(widget.login, widget.pass);
      devices = await starlineClient.getDevices();
      if (devices.isEmpty) {
        throw Exception('На аккаунте нет устройств StarLine');
      }
      var device = await _resolveDevice();
      if (device == null) {
        setState(() {
          isLoading = false;
          error = 'Устройство не выбрано';
        });
        return;
      }
      await _loadHistory(device);
    } on Exception catch (ex) {
      setState(() {
        error = ex.toString();
        isLoading = false;
      });
    }
  }

  /// Приоритет выбора: сохранённый из прошлой сессии (если актуален) →
  /// единственное устройство → единственное онлайн → диалог выбора.
  Future<StarlineDevice?> _resolveDevice() async {
    if (devices.length == 1) {
      return devices.first;
    }
    var prefs = await SharedPreferences.getInstance();
    var savedId = prefs.getString('device_id');
    var saved = devices.where((d) => d.deviceId == savedId).toList();
    if (saved.isNotEmpty) {
      return saved.first;
    }
    var online = devices.where((d) => d.isOnline).toList();
    if (online.length == 1) {
      return online.first;
    }
    return _showDevicePicker();
  }

  Future<StarlineDevice?> _showDevicePicker() {
    if (!mounted) return Future.value(null);
    return showDialog<StarlineDevice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Выберите автомобиль'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index];
              return ListTile(
                leading: const Icon(Icons.directions_car),
                title: Text(device.displayName),
                subtitle:
                    device.isOnline ? null : const Text('не в сети'),
                trailing: selectedDevice?.deviceId == device.deviceId
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(dialogContext).pop(device),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _changeDevice() async {
    var device = await _showDevicePicker();
    if (device == null || device.deviceId == selectedDevice?.deviceId) {
      return;
    }
    await _loadHistory(device);
  }

  EngineHoursCalculator _calculate() {
    return EngineHoursCalculator(lastRawHistory,
        maxSession: Duration(hours: maxSessionHours));
  }

  /// Настройка порога «правдоподобности» сессий. Пересчитывает
  /// результат по уже загруженной истории, без нового запроса.
  Future<void> _showSettingsDialog() async {
    var sliderValue = maxSessionHours.toDouble();
    var confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Максимальная длительность сессии'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Сессии длиннее этого времени не учитываются в моточасах '
                  '(например, когда событие остановки не записалось).'),
              Slider(
                min: 1,
                max: 24,
                divisions: 23,
                value: sliderValue,
                label: '${sliderValue.round()} ч',
                onChanged: (value) =>
                    setDialogState(() => sliderValue = value),
              ),
              Text('${sliderValue.round()} ч'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ОК'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || sliderValue.round() == maxSessionHours) {
      return;
    }
    maxSessionHours = sliderValue.round();
    var prefs = await SharedPreferences.getInstance();
    await prefs.setInt('max_session_hours', maxSessionHours);
    if (lastRawHistory != null) {
      setState(() {
        engineHours = _calculate();
      });
    }
  }

  /// Открывает страницу поддержки в браузере (платёжка CloudTips
  /// рассчитана на браузер: редиректы в банковские приложения).
  Future<void> _openDonation() async {
    try {
      await launchUrl(_donationUrl, mode: LaunchMode.externalApplication);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть страницу')),
        );
      }
    }
  }

  Future<void> _loadHistory(StarlineDevice device) async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      var response =
          await starlineClient.getHistory(widget.dateFrom, device.deviceId);
      var prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_id', device.deviceId);
      maxSessionHours = prefs.getInt('max_session_hours') ?? 8;
      lastRawHistory = response.data;
      setState(() {
        selectedDevice = device;
        engineHours = _calculate();
        isLoading = false;
      });
    } on Exception catch (ex) {
      setState(() {
        error = ex.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildAppBarTitle(),
        actions: [
          IconButton(
            tooltip: 'Поддержать разработчика',
            icon: const Icon(Icons.volunteer_activism),
            onPressed: _openDonation,
          ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  /// Заголовок: имя текущего авто; при нескольких устройствах оно
  /// становится кнопкой переключателя (со стрелкой раскрывающегося списка).
  Widget _buildAppBarTitle() {
    if (devices.length < 2 || selectedDevice == null) {
      return Text(selectedDevice?.displayName ?? '');
    }
    return Tooltip(
      message: 'Сменить автомобиль',
      child: TextButton(
        onPressed: isLoading ? null : _changeDevice,
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          textStyle: Theme.of(context).textTheme.titleLarge,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selectedDevice!.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.error_outline,
                color: Colors.redAccent, size: 60),
            const SizedBox(height: 16),
            Text(
              error!,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OverflowBar(
              alignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Назад'),
                ),
                ElevatedButton(
                  onPressed: _load,
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (engineHours == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      children: [
        _buildSummaryCard(),
        TripsChart(sessions: engineHours!.engineSessions),
        for (final day in engineHours!.engineSessionsByDate)
          EngineSessionsRow(day),
      ],
    );
  }

  /// Русская форма множественного числа: сессия / сессии / сессий.
  String _sessionsWord(int n) {
    final n10 = n % 10;
    final n100 = n % 100;
    if (n10 == 1 && n100 != 11) return 'сессия';
    if (n10 >= 2 && n10 <= 4 && (n100 < 10 || n100 >= 20)) return 'сессии';
    return 'сессий';
  }

  /// Русская форма множественного числа: час / часа / часов.
  String _hoursWord(int n) {
    final n10 = n % 10;
    final n100 = n % 100;
    if (n10 == 1 && n100 != 11) return 'час';
    if (n10 >= 2 && n10 <= 4 && (n100 < 10 || n100 >= 20)) return 'часа';
    return 'часов';
  }

  /// Шапка с итогом: число моточасов за период, период и
  /// статистика фильтра (сколько сессий учтено/исключено).
  Widget _buildSummaryCard() {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final sessions = engineHours!.engineSessions;
    final counted =
        sessions.where((s) => s.status == SessionStatus.ok).length;
    final excluded = sessions.length - counted;
    // Тонированная карточка-«герой» в тонах primary.
    final onContainer = scheme.onPrimaryContainer;
    return Card(
      margin: const EdgeInsets.all(8),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          children: [
            AutoSizeText(
              '${engineHours!.totalHours.inHours}',
              maxLines: 1,
              style: textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: onContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _hoursWord(engineHours!.totalHours.inHours),
              style:
                  textTheme.titleMedium?.copyWith(color: onContainer),
            ),
            const SizedBox(height: 12),
            Text(
              'с ${DateFormat('dd.MM.yyyy').format(widget.dateFrom)} по сегодня',
              style: textTheme.bodySmall?.copyWith(color: onContainer),
            ),
            const SizedBox(height: 4),
            Text(
              excluded > 0
                  ? 'учтено $counted ${_sessionsWord(counted)} · исключено $excluded'
                  : 'учтено $counted ${_sessionsWord(counted)}',
              style: textTheme.bodySmall?.copyWith(color: onContainer),
            ),
          ],
        ),
      ),
    );
  }
}
