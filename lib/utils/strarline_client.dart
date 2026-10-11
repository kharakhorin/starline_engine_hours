import 'dart:convert';
import 'dart:io';

import 'package:faker/faker.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';

class StarlineDevice {
  final String deviceId;
  final String alias;
  final int status; // > 0 — устройство онлайн, 0 — офлайн в момент запроса

  const StarlineDevice({
    required this.deviceId,
    required this.alias,
    this.status = 0,
  });

  bool get isOnline => status > 0;

  /// Имя для отображения: alias пользователя или запасной вариант.
  String get displayName =>
      alias.isNotEmpty ? alias : 'Устройство $deviceId';
}

/// Ошибка входа: текст уже человеческий, без сырого JSON.
class StarlineAuthException implements Exception {
  final String message;
  StarlineAuthException(this.message);

  @override
  String toString() => message;
}

/// Вход не прошёл: StarLine просит капчу (картинка по ссылке).
/// Подтверждается повторным логином с captchaSid + captchaCode.
class StarlineCaptchaException implements Exception {
  final String sid;
  final String imageUrl;
  StarlineCaptchaException(this.sid, this.imageUrl);

  @override
  String toString() => 'StarLine просит подтвердить, что ты не робот';
}

/// Вход не прошёл: нужен код из СМС (сервер его уже отправил).
/// Подтверждается повторным логином с smsCode.
class StarlineSmsException implements Exception {
  /// Телефон в замаскированном виде — таким его присылает сервер.
  final String phone;
  final int attemptsLeft;
  final int ttlSeconds;
  StarlineSmsException(this.phone, this.attemptsLeft, this.ttlSeconds);

  @override
  String toString() => 'Код отправлен СМС на $phone. '
      'Осталось попыток: $attemptsLeft, код действует '
      '${(ttlSeconds / 60).round()} мин.';
}

class StarlineClient {
  var userAgent = faker.internet.userAgent(osName: "Windows");
  var headers = {
    "content-type": "application/json",
    "accept-language": "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
  };
  var client = Dio();
  var cookieJar = CookieJar();

  StarlineClient() {
    client.options.headers = headers;
    client.options.baseUrl = 'https://starline-online.ru';
    client.interceptors.add(CookieManager(cookieJar));
    (client.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final httpClient = HttpClient();
      httpClient.userAgent = userAgent;
      return httpClient;
    };
  }

  /// Вход в личный кабинет StarLine через сайт.
  ///
  /// Успех — 200 с пустым телом (в dio 5 пустое тело приходит как null).
  /// Любой другой ответ несёт errors[] с полем title — по нему и
  /// понимаем, что именно не так: неверный пароль, капча, код из СМС.
  /// Капча подтверждается токеном Google reCAPTCHA (recaptchaCode —
  /// так делает сам сайт), СМС — кодом из сообщения. Повторная отправка
  /// СМС — refreshTfaCode.
  Future<void> login(String login, String pass,
      {String? captchaSid,
      String? recaptchaCode,
      String? smsCode,
      bool refreshTfaCode = false}) async {
    var body = json.encode({
      "username": login,
      "password": pass,
      if (captchaSid != null && recaptchaCode != null) ...{
        "captchaSid": captchaSid,
        "recaptchaCode": recaptchaCode,
      },
      if (smsCode != null) "smsCode": smsCode,
      if (refreshTfaCode) "refreshTfaCode": true,
    });
    dynamic data;
    int? status;
    try {
      var response = await client.post('/rest/security/login', data: body);
      data = response.data;
    } on DioException catch (e) {
      data = e.response?.data;
      status = e.response?.statusCode;
    }
    final raw = data?.toString().trim() ?? '';
    if (raw.isEmpty && status == null) return;

    final authError = parseLoginError(data);
    if (authError != null) throw authError;

    // Ничего знакомого в ответе нет — показываем его как есть,
    // обрезав: по нему можно понять, что придумал сервер.
    final serverText = findErrorText(data);
    final detail = serverText ??
        (raw.isEmpty
            ? 'код ответа $status'
            : (raw.length > 200 ? '${raw.substring(0, 200)}…' : raw));
    throw StarlineAuthException(
        'Не удалось войти в StarLine. $detail.\n\n'
        'Если логин и пароль верные, открой starline.online, войди там '
        'один раз и нажми «Повторить».');
  }

  /// Разбор ответа логина: по errors[].title понимаем, что случилось.
  /// Возвращает null, если ошибки не разпознаны.
  static Exception? parseLoginError(dynamic data) {
    if (data is! Map) return null;
    final errors = data['errors'];
    if (errors is! List || errors.isEmpty) return null;
    final error = errors.first;
    if (error is! Map) return null;
    final title = error['title']?.toString() ?? '';
    final code = error['code'];
    final meta = error['meta'];
    switch (title) {
      case 'index.error.wrongUserNameOrPassword':
        return StarlineAuthException('Неверный логин или пароль.');
      case 'index.error.captcha':
        final sid = meta?['captchaSid']?.toString() ?? '';
        final img = meta?['captchaImg']?.toString() ?? '';
        if (sid.isNotEmpty) return StarlineCaptchaException(sid, img);
        return StarlineAuthException(
            'StarLine просит капчу. Открой starline.online, войди там '
            'один раз и нажми «Повторить».');
      case 'TFA_REQUIRED':
        return StarlineSmsException(
          meta?['phone']?.toString() ?? 'твой телефон',
          (meta?['attemptsLeft'] as num?)?.toInt() ?? 0,
          (meta?['ttl'] as num?)?.toInt() ?? 0,
        );
      default:
        return StarlineAuthException(
            'Ошибка входа: ${title.isEmpty ? 'код $code' : title}');
    }
  }

  /// Публичный ключ reCAPTCHA с логин-страницы сайта: он нужен,
  /// чтобы показать капчу в приложении. Ключ сидит в SERVER_VARS.
  Future<String> fetchRecaptchaSiteKey() async {
    var response = await client.get('/');
    var html = response.data.toString();
    var match = RegExp('recaptchaSiteKey["\'\\s]*[:=]["\'\\s]*([A-Za-z0-9_-]+)')
        .firstMatch(html);
    if (match == null) {
      throw Exception('Не удалось получить ключ капчи с сайта StarLine');
    }
    return match.group(1)!;
  }

  /// Ищет в теле ответа StarLine текст ошибки: сервер кладёт его
  /// в поля text/message/desc/description на разной глубине.
  static String? findErrorText(dynamic node) {
    if (node is Map) {
      for (final key in const ['text', 'message', 'desc', 'description']) {
        final value = node[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      for (final value in node.values) {
        final found = findErrorText(value);
        if (found != null) return found;
      }
    } else if (node is List || node is Iterable) {
      for (final value in node) {
        final found = findErrorText(value);
        if (found != null) return found;
      }
    }
    return null;
  }

  Future<List<StarlineDevice>> getDevices() async {
    Response response;
    try {
      response = await client.get('/device');
    } on DioException catch (e) {
      throw Exception('Сервер StarLine недоступен '
          '(${e.response?.statusCode ?? 'нет связи'})');
    }
    if (response.statusCode != 200) {
      throw Exception('Ошибка получения списка устройств:\n${response.data}');
    }
    try {
      return parseDevices(response.data);
    } on TypeError {
      // Пришло что-то кроме списка устройств — например, текст ошибки.
      throw Exception('Неожиданный ответ сервера при получении устройств: '
          '${findErrorText(response.data) ?? 'нет описания'}');
    }
  }

  /// Разбор ответа GET /device: answer.devices[] c device_id и alias.
  /// Офлайн-устройства (status == 0) не отбрасываются — машина может быть
  /// просто не в сети в момент запроса, — но уходят в конец списка.
  static List<StarlineDevice> parseDevices(dynamic data) {
    final devices = (data["answer"]["devices"] as List)
        .map<StarlineDevice>((json) => StarlineDevice(
              deviceId: json["device_id"].toString(),
              alias: (json["alias"] ?? "").toString().trim(),
              status: (json["status"] as num?)?.toInt() ?? 0,
            ))
        .toList();
    devices.sort((a, b) {
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      return a.displayName.compareTo(b.displayName);
    });
    return devices;
  }

  Future<Response> getHistory(DateTime dateFrom, String deviceId) async {
    var dateTo =
        DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
    var dateStart =
        dateFrom.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;

    Response response;
    try {
      response = await client.get(
        '/events/history?startTime=$dateStart&endTime=$dateTo&deviceId=$deviceId',
      );
    } on DioException catch (e) {
      throw Exception('Сервер StarLine недоступен '
          '(${e.response?.statusCode ?? 'нет связи'})');
    }

    if (response.statusCode != 200) {
      throw Exception('Ошибка получения событий:\n${response.data}');
    }

    return response;
  }
}
