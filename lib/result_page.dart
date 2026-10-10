import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/engine_hours_calculator.dart';
import 'utils/strarline_client.dart';
import 'widgets/engine_session_row.dart';

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
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  /// Заголовок: пока авто не выбрано или оно одно — просто «Моточасы»;
  /// при нескольких устройствах имя текущего авто становится кнопкой
  /// переключателя (со стрелкой раскрывающегося списка).
  Widget _buildAppBarTitle() {
    if (devices.length < 2 || selectedDevice == null) {
      return const Text('Моточасы');
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
                'Моточасы · ${selectedDevice!.displayName}',
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
    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              margin: const EdgeInsets.all(10.0),
              alignment: Alignment.center,
              child: SizedBox(
                  width: 150,
                  height: 150,
                  child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.blueAccent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.blue[800]!,
                          width: 6,
                        ),
                      ),
                      child: AutoSizeText(
                          '${engineHours!.totalHours.inHours}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 110))))),
          ),
          floating: true,
          expandedHeight: 200,
          automaticallyImplyLeading: false,
          toolbarHeight: 0),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              return EngineSessionsRow(
                  engineHours!.engineSessionsByDate[index]);
            },
            childCount: engineHours!.engineSessionsByDate.length,
          ),
        ),
      ],
    );
  }
}
