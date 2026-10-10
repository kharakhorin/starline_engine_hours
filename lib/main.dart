import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starline_engine_hours/widgets/pssword_field.dart';
import 'result_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Единый seed: от него генерируются и светлая, и тёмная темы.
  static const _seedColor = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        // Светлая и тёмная темы от одного seed, переключение — по
        // системной настройке устройства.
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _seedColor,
            brightness: Brightness.dark,
          ),
        ),
        home: const LoginDemo(),
        localizationsDelegates: const [
          GlobalWidgetsLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ru', 'RU')
        ]);
  }
}

class LoginDemo extends StatefulWidget {
  const LoginDemo({super.key});

  @override
  State<LoginDemo> createState() => _LoginDemoState();
}

class _LoginDemoState extends State<LoginDemo> {
  final date = TextEditingController();
  final login = TextEditingController();
  final pass = TextEditingController();
  DateTime selectedDate = DateTime.now();
  bool rememberMe = false;
  bool isButtonEnabled = false;
  late final SharedPreferences prefs;

  @override
  void initState() {
    super.initState();
    loadFormData().then((value) => isFormDataEmpty());
  }

  Future<void> loadFormData() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      login.text = (prefs.getString('login') ?? '');
      pass.text = (prefs.getString('pass') ?? '');
      selectedDate =
          DateTime.tryParse(prefs.getString('date') ?? '') ?? DateTime.now();
      date.text = DateFormat('dd.MM.yyyy').format(selectedDate);
      rememberMe = (prefs.getBool('rememberMe') ?? false);
    });
  }

  void saveFormData() {
    if (rememberMe) {
      prefs.setString('login', login.text);
      prefs.setString('pass', pass.text);
      prefs.setString('date', selectedDate.toIso8601String());
      prefs.setBool('rememberMe', rememberMe);
    } else {
      prefs.clear();
      rememberMe = false;
    }
  }

  void isFormDataEmpty() {
    setState(() {
      if ((login.text.trim().isNotEmpty) && (pass.text.trim().isNotEmpty)) {
        isButtonEnabled = true;
      } else {
        isButtonEnabled = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("Моточасы StarLine"),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 16),
                  Center(
                    child: SizedBox(
                        height: 150,
                        width: 200,
                        child: Image.asset('assets/car-engine.png')),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: login,
                    onChanged: (val) => isFormDataEmpty(),
                    decoration: const InputDecoration(
                        labelText: 'Логин',
                        hintText: 'Введите логин Starline'),
                  ),
                  const SizedBox(height: 16),
                  PasswordField(
                      onChanged: (val) => isFormDataEmpty(),
                      controller: pass,
                      labelText: 'Пароль',
                      hintText: 'Введите пароль Starline'),
                  const SizedBox(height: 16),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SizedBox(
                            width: 190,
                            child: TextField(
                              controller: date,
                              readOnly: true,
                              decoration: const InputDecoration(
                                icon: Icon(Icons.event),
                                labelText: 'Дата начала отсчёта',
                              ),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime.now()
                                      .subtract(const Duration(days: 365)),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setState(() {
                                    selectedDate = picked;
                                    date.text = DateFormat('dd.MM.yyyy')
                                        .format(picked);
                                  });
                                }
                              },
                            )),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() {
                              rememberMe = !rememberMe;
                            });
                          },
                          child: Row(
                            children: [
                              Checkbox(
                                value: rememberMe,
                                onChanged: (value) {
                                  setState(() {
                                    rememberMe = value!;
                                  });
                                },
                              ),
                              const Text('Запомнить'),
                            ],
                          ),
                        )
                      ]),
                  const SizedBox(height: 24),
                  SizedBox(
                      height: 56,
                      child: FilledButton(
                          onPressed: isButtonEnabled
                              ? () {
                                  saveFormData();
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => ResultsPage(
                                              login: login.text,
                                              pass: pass.text,
                                              dateFrom: selectedDate)));
                                }
                              : null,
                          child: const Text('Посчитать'))),
                ],
              ),
            ),
          ),
        ));
  }
}
