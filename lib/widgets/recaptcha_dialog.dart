import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Диалог с Google reCAPTCHA — той же, что показывает сайт StarLine.
/// Виджет живёт в мини-вебвью с baseUrl сайта (ключ привязан к домену),
/// решённый токен уезжает в Flutter через JavaScriptChannel.
class RecaptchaDialog extends StatefulWidget {
  final String siteKey;

  /// Тема виджета капчи под тему приложения: в initState контекст
  /// для Theme.of ещё недоступен, поэтому передаём снаружи.
  final bool isDark;

  const RecaptchaDialog({
    super.key,
    required this.siteKey,
    required this.isDark,
  });

  @override
  State<RecaptchaDialog> createState() => _RecaptchaDialogState();
}

class _RecaptchaDialogState extends State<RecaptchaDialog> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Голому webview Google не доверяет и заваливает заданиями:
      // убираем из UA метку встроенного браузера.
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36')
      ..addJavaScriptChannel('Captcha', onMessageReceived: (message) {
        if (message.message.isNotEmpty && mounted) {
          Navigator.of(context).pop(message.message);
        }
      });
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      // Риск-скорингу reCAPTCHA нужны сторонние куки (DOM-хранилище
      // webview_flutter_android включает сам).
      AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ).setAcceptThirdPartyCookies(platform, true);
    }
    _controller.loadHtmlString(
      _html(widget.siteKey, widget.isDark),
      // Ключ reCAPTCHA выдан домену сайта, поэтому притворяемся им.
      baseUrl: 'https://starline-online.ru/',
    );
  }

  static String _html(String siteKey, bool isDark) => '''
    <!DOCTYPE html><html><head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <script src="https://www.recaptcha.net/recaptcha/api.js?onload=onloadCallback&render=explicit&hl=ru" async defer></script>
    <script>
      var onloadCallback = function() {
        grecaptcha.render('captcha', {
          'sitekey': '$siteKey',
          'theme': '${isDark ? 'dark' : 'light'}',
          'callback': function(response) { Captcha.postMessage(response); }
        });
      };
    </script></head>
    <body style="margin:0;padding:8px;display:flex;justify-content:center;align-items:flex-start">
    <div id="captcha"></div></body></html>
  ''';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Подтверждение входа'),
      // Высокий контент: всплывающее задание reCAPTCHA («выбери
      // автобусы») выше самой галочки, в низкой плашке оно резалось.
      content: SizedBox(
        width: 330,
        height: 520,
        child: WebViewWidget(controller: _controller),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('Отмена'),
        ),
      ],
    );
  }
}
