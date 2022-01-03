import 'package:flutter/material.dart';
import 'utils/engine_hours_calculator.dart';
import 'utils/strarline_client.dart';
import 'widgets/engine_session_row.dart';
import 'package:dio/dio.dart';
import 'package:auto_size_text/auto_size_text.dart';

// ignore: must_be_immutable
class ResultsPage extends StatelessWidget {
  DateTime dateFrom;
  String login;
  String pass;
  bool isLoading = false;
  bool isSucsess = true;
  StarlineClient starlineClient = StarlineClient();
  late Response<dynamic> loginResponse;
  late Response<dynamic> historyResponse;

  ResultsPage(
      {Key? key,
      required this.login,
      required this.pass,
      required this.dateFrom})
      : super(key: key);

  Future<dynamic> getHistory() async {
    try {
      loginResponse = await starlineClient.login(login, pass);
      historyResponse = await starlineClient.getHistory(dateFrom);
      return historyResponse.data;
    } on Exception catch (ex) {
      isSucsess = false;
      return ex.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Моточасы"),
      ),
      body: FutureBuilder(
        future: getHistory(),
        builder: (BuildContext context, AsyncSnapshot<dynamic> response) {
          if (response.hasData) {
            if (isSucsess) {
              var engineHours = EngineHoursCalculator(response.data!);
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
                                  child: AutoSizeText(
                                      engineHours.totalHours.inHours.toString(),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 110)))),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.blue[800]!,
                              width: 6,
                            ),
                          ),
                        ),
                      ),
                      floating: true,
                      expandedHeight: 200,
                      automaticallyImplyLeading: false,
                      toolbarHeight: 0),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext context, int index) {
                        return EngineSessionsRow(
                            engineHours.engineSessionsByDate[index]);
                      },
                      childCount: engineHours.engineSessionsByDate.length,
                    ),
                  ),
                ],
              );
            } else {
              return AlertDialog(
                  content: Text(response.data.toString()),
                  actions: <Widget>[
                    TextButton(
                        child: const Text('Назад'),
                        onPressed: () {
                          Navigator.of(context).pop();
                        })
                  ]);
            }
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}
