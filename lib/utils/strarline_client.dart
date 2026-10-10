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

  Future<Response> login(String login, String pass) async {
    var body = json.encode({"username": login, "password": pass});
    var response = await client.post('/rest/security/login', data: body);
    // Успешный логин StarLine возвращает 200 с пустым телом
    // (в dio 5 пустое тело приходит как null, а не как "").
    final data = response.data;
    if (data != null && data.toString().trim().isNotEmpty) {
      throw Exception('Ошибка авторизации:\n$data');
    }
    return response;
  }

  Future<List<StarlineDevice>> getDevices() async {
    var response = await client.get('/device');
    if (response.statusCode != 200) {
      throw Exception('Ошибка получения списка устройств:\n${response.data}');
    }
    return parseDevices(response.data);
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

    var response = await client.get(
      '/events/history?startTime=$dateStart&endTime=$dateTo&deviceId=$deviceId',
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка получения событий:\n${response.data}');
    }

    return response;
  }
}
