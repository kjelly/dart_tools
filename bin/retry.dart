import 'dart:io';

import 'package:args/args.dart';

Future main(List<String> args) async {
  var parser = ArgParser(allowTrailingOptions: false);
  parser.addOption('interval',
      abbr: 'i', defaultsTo: '1', valueHelp: 'seconds');
  parser.addOption('retry',
      abbr: "r", defaultsTo: '0', valueHelp: 'retry count. 0 for infinity.');
  parser.addFlag('help');
  var argResults = parser.parse(args);
  if (argResults['help']) {
    print(parser.usage);
    return;
  }

  if (argResults.rest.isEmpty) {
    print('Please provide a command.');
    exit(0);
  }
  var retry = int.tryParse(argResults['retry']) ?? 0;
  final infinity = retry == 0;
  final interval = int.tryParse(argResults['interval']) ?? 1;
  final program = argResults.rest.first;
  final programArgs = argResults.rest.sublist(1);
  Process? p;
  var exitCode = -1;
  while (retry > 0 || infinity) {
    try {
      p = await Process.start(program, programArgs,
          runInShell: true, mode: ProcessStartMode.inheritStdio);
      exitCode = await p.exitCode;
      if (exitCode == 0) {
        break;
      }
    } catch (e) {
      print(e);
    }
    retry--;
    await Future.delayed(Duration(seconds: interval));
  }
  exit(exitCode);
}
