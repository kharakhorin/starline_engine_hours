import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starline_engine_hours/widgets/pssword_field.dart';
import 'result_page.dart';
import 'package:date_time_picker/date_time_picker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: LoginDemo(),
        localizationsDelegates: [
          GlobalWidgetsLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [
          Locale('ru', 'RU')
        ]);
  }
}

class LoginDemo extends StatefulWidget {
  const LoginDemo({Key? key}) : super(key: key);

  @override
  _LoginDemoState createState() => _LoginDemoState();
}

class _LoginDemoState extends State<LoginDemo> {
  final date = TextEditingController();
  final login = TextEditingController();
  final pass = TextEditingController();
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
      date.text = prefs.getString('date') ?? DateTime.now().toString();
      rememberMe = (prefs.getBool('rememberMe') ?? false);
    });
  }

  void saveFormData() {
    if (rememberMe) {
      prefs.setString('login', login.text);
      prefs.setString('pass', pass.text);
      prefs.setString('date', date.text);
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
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text("Моточасы StarLine"),
        ),
        body: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 30.0, bottom: 20),
                    child: Center(
                      child: SizedBox(
                          height: 150,
                          width: 200,
                          child: Image.asset('assets/car-engine.png')),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: TextField(
                      controller: login,
                      onChanged: (val) => isFormDataEmpty(),
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Логин',
                          hintText: 'Введите логин Starline'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 15.0, right: 15.0, top: 0, bottom: 15),
                    child: PasswordField(
                        onChanged: (val) => isFormDataEmpty(),
                        controller: pass,
                        labelText: 'Пароль',
                        hintText: 'Введите пароль Starline'),
                  ),
                  Padding(
                      padding: const EdgeInsets.only(
                          left: 30.0, right: 30.0, top: 0, bottom: 25),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SizedBox(
                                //height: 100,
                                width: 170,
                                child: DateTimePicker(
                                  //initialValue: date.toString(),
                                  dateMask: 'dd.MM.yyyy',
                                  icon: const Icon(Icons.event),
                                  firstDate: DateTime.now()
                                      .subtract(const Duration(days: 365)),
                                  lastDate: DateTime.now(),
                                  dateLabelText: 'Дата начала отсчёта',
                                  controller: date,
                                )),
                            Row(
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
                            )
                          ])),
                  SizedBox(
                      width: 150.0,
                      height: 60.0,
                      child: ElevatedButton(
                          child: const Text(
                            'Посчитать',
                            style: TextStyle(fontSize: 20),
                          ),
                          onPressed: isButtonEnabled
                              ? () {
                                  saveFormData();
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => ResultsPage(
                                              login: login.text,
                                              pass: pass.text,
                                              dateFrom:
                                                  DateTime.parse(date.text))));
                                }
                              : null)),
                ],
              ),
            ),
          ),
        ));
  }
}
