import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Кнопка «Поддержать разработчика» (CloudTips) для AppBar.
/// Открывает [open] — им же пользуется карточка поддержки
/// на экране результата.
class DonationButton extends StatelessWidget {
  const DonationButton({super.key});

  // Платёжка CloudTips рассчитана на браузер: редиректы в банковские
  // приложения, поэтому открываем её внешним браузером.
  static final Uri _url = Uri.parse('https://pay.cloudtips.ru/p/20f12342');

  /// Открывает страницу поддержки в браузере. Общий код для кнопки
  /// в AppBar и карточки на экране результата.
  static Future<void> open() async {
    try {
      await launchUrl(_url, mode: LaunchMode.externalApplication);
    } on Exception {
      // Ничего не делаем: страница поддержки — необязательная
      // функциональность, ругаться на неё незачем.
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Поддержать разработчика',
      icon: const Icon(Icons.volunteer_activism),
      onPressed: open,
    );
  }
}
