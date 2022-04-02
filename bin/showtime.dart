import 'dart:io';
import 'dart:convert';
import 'package:args/args.dart';
import 'package:intl/intl.dart';

void main(List<String> args) async {
  var parser = ArgParser();
  parser.addFlag('utc');
  parser.addOption('time-format', defaultsTo: 'yyyy-MM-dd H:m:s');
  final results = parser.parse(args);

  final timeFormat = results['time-format'];
  final DateFormat formatter = DateFormat(timeFormat);
  final isUtc = results['utc'];

  void output(Stream s) {
    s.transform(utf8.decoder).transform(const LineSplitter()).listen((data) {
      String now;
      if (isUtc) {
        now = formatter.format(DateTime.now().toUtc());
      } else {
        now = formatter.format(DateTime.now());
      }
      stdout.write('$now : $data \n');
    });
  }

  if (results.rest.isEmpty) {
    output(stdin);
  } else {
    var p = await Process.start(results.rest[0], results.rest.sublist(1));
    output(p.stdout);
    output(p.stderr);
    await p.exitCode;
  }
}
