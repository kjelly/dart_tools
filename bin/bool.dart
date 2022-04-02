import 'dart:io';

import 'package:args/args.dart';

Future<ProcessResult> run(String command) {
  return Process.run('bash', ['-c', command]);
}

void main(List<String> args) async {
  var parser = ArgParser();
  parser.addFlag('help', abbr: "h", negatable: false);
  parser.addFlag('not',
      abbr: "n",
      defaultsTo: false,
      help: 'show the result even if the command failed');
  parser.addFlag('and',
      abbr: "a",
      defaultsTo: false,
      help: 'show the result even if the command failed');
  parser.addFlag('or',
      abbr: "o",
      defaultsTo: false,
      help: 'show the result even if the command failed');
  parser.addFlag('xor',
      abbr: "x",
      defaultsTo: false,
      help: 'show the result even if the command failed');

  parser.addOption('worker', abbr: 'w', defaultsTo: "5");

  var argResults = parser.parse(args);
  var done = 0;
  var exitCodeList = List<int>.filled(argResults.rest.length, -1);
  var lastIndex = argResults.rest.length - 1;

  var worker = int.tryParse(argResults['worker']) ?? 5;

  if (argResults['help']) {
    print(parser.usage);
    return;
  }
  if (argResults.rest.isEmpty) {
    print("Please provide command");
    print(parser.usage);
    return;
  }

  for (var i = 0; i < argResults.rest.length; i++) {
    while (worker <= 0) {
      await Future.delayed(Duration(milliseconds: 1));
    }
    var command = argResults.rest[i];
    var index = i;
    run(command).then((p) {
      done += 1;
      worker += 1;
      print(p.stdout);
      print(p.stderr);
      exitCodeList[index] = p.exitCode;
    });
    worker -= 1;
  }

  while (done < argResults.rest.length) {
    await Future.delayed(Duration(milliseconds: 1));
  }

  if (argResults['not']) {
    if (exitCodeList[lastIndex] == 0) {
      exit(1);
    } else {
      exit(0);
    }
  }
  if (argResults['and']) {
    for (var i in exitCodeList) {
      if (i != 0) {
        exit(1);
      }
    }
    exit(0);
  }
  if (argResults['or']) {
    for (var i in exitCodeList) {
      if (i == 0) {
        exit(0);
      }
    }
    exit(1);
  }
}
