import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'utils/engine_hours_calculator.dart';
import 'utils/starline_client.dart';
import 'widgets/donation_button.dart';
import 'widgets/engine_session_row.dart';
import 'widgets/recaptcha_dialog.dart';
import 'widgets/trips_chart.dart';

/// Личный кабинет: один вход через браузер снимает капчу/СМС,
/// после этого логин из приложения проходит.
final Uri _siteUrl = Uri.parse('https://starline-online.ru');

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

  /// Ошибка именно входа: для неё показываем кнопку «открыть сайт».
  bool isAuthError = false;
  bool isLoading = false;

  /// Подтверждение входа: капча и код из СМС досылаются повторным
  /// логином с этими значениями.
  String? _captchaSid;
  String? _recaptchaCode;
  String? _smsCode;
  bool _resendSms = false;

  /// Сырой ответ истории — чтобы менять порог без нового запроса.
  dynamic lastRawHistory;
  int maxSessionHours = 8;

  /// Карточка поддержки: появляется после третьего успешного расчёта
  /// и живёт, пока пользователь её не закроет крестиком.
  bool _showDonationCard = false;

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
      await starlineClient.login(widget.login, widget.pass,
          captchaSid: _captchaSid,
          recaptchaCode: _recaptchaCode,
          smsCode: _smsCode,
          refreshTfaCode: _resendSms);
      // Вход прошёл — подтверждения больше не нужны.
      _captchaSid = null;
      _recaptchaCode = null;
      _smsCode = null;
      _resendSms = false;
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
    } on StarlineCaptchaException catch (ex) {
      // Сервер сменил капчу — запоминаем новый sid и показываем
      // reCAPTCHA (текст с картинки сайт не принимает).
      _captchaSid = ex.sid;
      _recaptchaCode = null;
      _smsCode = null;
      setState(() => isLoading = false);
      await _showCaptchaDialog(ex);
    } on StarlineSmsException catch (ex) {
      _smsCode = null;
      _resendSms = false;
      setState(() => isLoading = false);
      await _showSmsDialog(ex);
    } on StarlineAuthException catch (ex) {
      // Финальная ошибка — подтверждения сбрасываем, чтобы
      // «Повторить» начинал с чистого входа.
      _captchaSid = null;
      _recaptchaCode = null;
      _smsCode = null;
      _resendSms = false;
      setState(() {
        error = ex.message;
        isAuthError = true;
        isLoading = false;
      });
    } on Exception catch (ex) {
      setState(() {
        error = ex.toString();
        isAuthError = false;
        isLoading = false;
      });
    }
  }

  /// Капча: та же Google reCAPTCHA, что на сайте StarLine, в мини-вебвью.
  /// Токен уходит повторным логином с captchaSid + recaptchaCode.
  Future<void> _showCaptchaDialog(StarlineCaptchaException ex) async {
    if (!mounted) return;
    String siteKey;
    try {
      siteKey = await starlineClient.fetchRecaptchaSiteKey();
    } on Exception {
      setState(() {
        error = 'StarLine просит капчу, но получить её настройки '
            'не удалось.\n\nВойди на starline.online в браузере и нажми '
            '«Повторить».';
        isAuthError = true;
      });
      return;
    }
    if (!mounted) return;
    final token = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RecaptchaDialog(
        siteKey: siteKey,
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
    );
    if (token != null && token.isNotEmpty) {
      _recaptchaCode = token;
      _load();
    } else {
      setState(() {
        error = '${ex.toString()}\n\n'
            'Войди на starline.online в браузере и нажми «Повторить».';
        isAuthError = true;
      });
    }
  }

  /// Код из СМС: сервер уже отправил его, вводим и подтверждаем
  /// повторным логином с smsCode. Код можно переспросить —
  /// refreshTfaCode (так делает сайт).
  Future<void> _showSmsDialog(StarlineSmsException ex) async {
    if (!mounted) return;
    final code = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Код из СМС'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ex.toString()),
            TextField(
              controller: code,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Код из СМС'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
              _resendSms = true;
              _load();
            },
            child: const Text('Прислать ещё раз'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Войти'),
          ),
        ],
      ),
    );
    if (confirmed == true && code.text.trim().isNotEmpty) {
      _smsCode = code.text.trim();
      _load();
    } else {
      setState(() {
        error = '${ex.toString()}\n\n'
            'Повтори позже или отключи вход по СМС в личном кабинете.';
        isAuthError = true;
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

  /// Пользователь закрыл карточку поддержки — больше не показываем.
  Future<void> _hideDonationCard() async {
    setState(() => _showDonationCard = false);
    var prefs = await SharedPreferences.getInstance();
    await prefs.setBool('donation_card_dismissed', true);
  }

  /// Карточка поддержки под итогом: тихая, без давления — заголовок,
  /// пара строк и кнопка.
  Widget _buildDonationCard() {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Мягкий кружок в тонах secondary: рифмуется с сердцем
            // из AppBar, но не спорит с карточкой-итогом.
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.volunteer_activism,
                size: 20,
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Приложение бесплатное',
                      style: textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    'Без рекламы и подписок. Если оно тебе помогает, '
                    'автор будет рад поддержке',
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: DonationButton.open,
                    child: const Text('Поддержать'),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Больше не показывать',
              visualDensity: VisualDensity.compact,
              onPressed: _hideDonationCard,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
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
      // Карточка поддержки: с третьего расчёта, если её не закрывали.
      var calculations = (prefs.getInt('calculations_count') ?? 0) + 1;
      await prefs.setInt('calculations_count', calculations);
      _showDonationCard = calculations >= 3 &&
          !(prefs.getBool('donation_card_dismissed') ?? false);
      lastRawHistory = response.data;
      setState(() {
        selectedDevice = device;
        engineHours = _calculate();
        isLoading = false;
      });
    } on Exception catch (ex) {
      setState(() {
        error = ex.toString();
        isAuthError = false;
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
          const DonationButton(),
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
            if (isAuthError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton.icon(
                  onPressed: () => launchUrl(_siteUrl,
                      mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Открыть starline.online'),
                ),
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
        if (_showDonationCard) _buildDonationCard(),
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
