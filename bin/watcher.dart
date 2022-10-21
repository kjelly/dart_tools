import 'dart:io';
import 'dart:convert';
import 'package:args/args.dart';
import 'package:collection/collection.dart';

Future main(List<String> arguments) async {
  var parser = ArgParser();
  parser.addFlag('loop', abbr: 'l', help: 'Loop forever');
  parser.addOption('ok', abbr: 'o', help: 'OK to run');
  parser.addFlag('verbose', abbr: 'v', help: 'verbose');
  parser.addOption('sleep', abbr: 's', help: 'Sleep time', defaultsTo: '1');
  parser.addOption('fail', abbr: 'f', help: 'Fail to run');
  parser.addOption('fail-times',
      abbr: 't', help: 'Fail times', defaultsTo: '5');
  var results = parser.parse(arguments);
  var ok = results['ok'];
  var fail = results['fail'];
  var loop = results['loop'];
  var command = results.rest[0];
  var verbose = results['verbose'];
  var maxFialTimes = int.tryParse(results['fail-times']) ?? 5;
  var sleepTime = int.tryParse(results['sleep']) ?? 0;
  var failTimes = 0;
  var commandArgs = results.rest.sublist(1);

  while (true) {
    var pr = await Process.run(command, commandArgs);
    if (pr.exitCode == 0) {
      failTimes = 0;
    } else if (pr.exitCode != 0 && fail != null) {
      failTimes++;

      if (verbose) {
        print('${pr.exitCode} ${pr.stdout} ${pr.stderr}');
      }
    }
    if (failTimes >= maxFialTimes) {
      pr = await Process.run('bash', ['-c', fail]);

      if (verbose) {
        print('${pr.exitCode} ${pr.stdout} ${pr.stderr}');
      }
      failTimes = 0;
    }
    await Future.delayed(Duration(seconds: sleepTime));
    if (!loop) break;
  }
}
