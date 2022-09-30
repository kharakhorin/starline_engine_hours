import 'dart:convert';
import 'dart:io';
import 'package:faker/faker.dart';
import 'package:dio/dio.dart';
import 'package:dio/adapter.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';

class StarlineClient {
  var userAgent = faker.internet.userAgent(osName: "Windows");
  var headers = {
    "content-type": "application/json",
  };
  var client = Dio();
  var cookieJar = CookieJar();

  StarlineClient() {
    client.options.headers = headers;
    client.options.baseUrl = 'https://starline-online.ru';
    client.interceptors.add(CookieManager(cookieJar));
    (client.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
        (HttpClient client) {
      client.userAgent = userAgent;
      return null;
    };
  }

  Future<Response> login(String login, String pass) async {
    var body = json.encode({"username": login, "password": pass});
    var response = await client.post('/rest/security/login', data: body);
    if (response.data.toString().isNotEmpty) {
      throw Exception('Ошибка автоирзации:\n' + response.data.toString());
    }
    return response;
  }

  Future<String?> getDeviceId() async {
    var response = await client.get('/device');
    if (response.statusCode != 200) {
      throw Exception(
          'Ошибка получения ид устройства:\n' + response.data.toString());
    }
    return response.data["answer"]["devices"][0]["device_id"].toString();
  }

  Future<Response> getHistory(DateTime dateFrom) async {
    var dateTo =
        DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
    var dateStart =
        dateFrom.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
    String? deviceId = await getDeviceId();

    var response = await client.get(
      '/events/history?startTime=$dateStart&endTime=$dateTo&deviceId=$deviceId',
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка получения событий:\n' + response.data.toString());
    }

    return response;
  }
}
