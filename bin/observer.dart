import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:args/args.dart';

Future main(List<String> args) async {
  var parser = ArgParser();
  parser.addMultiOption('command', abbr: 'c', help: 'command to observer.');
  parser.addMultiOption('final', abbr: 'f', help: 'final');
  parser.addMultiOption('loop',
      abbr: 'l', help: 'command for loop to observer');
  parser.addOption('loop-delay',
      help: 'delay for loop', valueHelp: 'seconds', defaultsTo: '1');
  parser.addOption('delay',
      abbr: 'd', help: 'delay', valueHelp: 'seconds', defaultsTo: '0');

  late ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    print(e.message);
    print(parser.usage);
    exit(1);
  }
  if (results.rest.isEmpty) {
    print(parser.usage);
    exit(1);
  }

  var mainCommand = results.rest.first;
  var mainArgs = results.rest.skip(1).toList();
  var command = results['command'];
  var finalCommand = results['final'];
  var loopObserver = results['loop'];
  var loopObserverOutput = <String>[];
  Process? mainProcess;
  var observerProcesses = <Process>[];
  var observerOutput = <String>[];
  var finish = false;
  var timerList = <Timer>[];
  Map<String, int> commandToIndex = {};
  final delay = Duration(seconds: int.tryParse(results['delay']) ?? 0);
  Process.start(mainCommand, mainArgs).then((p) async {
    mainProcess = p;
    Map<String, String> env = Map.from(Platform.environment);
    env['PID'] = '${p.pid}';
    p.stdout.listen(stdout.add);
    p.stderr.listen(stderr.add);
    var index = -1;
    for (var i in command) {
      observerOutput.add('');
      index += 1;
      final _index = index;
      Process.start('bash', ['-c', i], environment: env).then((p) async {
        observerProcesses.add(p);
        p.stdout.transform(utf8.decoder).listen((data) {
          observerOutput[_index] += data;
        });
        p.stderr.transform(utf8.decoder).listen((data) {
          observerOutput[_index] += data;
        });
      });
    }

    index = -1;
    for (var i in loopObserver) {
      loopObserverOutput.add('');
      index += 1;
      final _index = index;
      commandToIndex[i] = _index;

      dynamic _run() async {
        Process.start('bash', ['-c', i], environment: env).then((p) async {
          observerProcesses.add(p);
          p.stdout.transform(utf8.decoder).listen((data) {
            loopObserverOutput[_index] += data;
          });
          p.stderr.transform(utf8.decoder).listen((data) {
            loopObserverOutput[_index] += data;
          });
        });
      }

      Timer.run(_run);
      timerList.add(Timer.periodic(
          Duration(seconds: int.tryParse(results['loop-delay']) ?? 1),
          (t) async {
        _run();
        if (finish) {
          t.cancel();
        }
      }));
    }
  });
  await Future.doWhile(() async {
    await Future.delayed(Duration(seconds: 1));
    return mainProcess == null;
  });
  await mainProcess?.exitCode;
  await Future.delayed(delay);
  finish = true;
  for (var p in observerProcesses) {
    p.kill();
  }
  for (var p in observerProcesses) {
    await p.exitCode;
  }
  for (var i = 0; i < observerOutput.length; i++) {
    print('command: ${command[i]}');
    print(observerOutput[i]);
  }

  for (var i = 0; i < loopObserverOutput.length; i++) {
    print('command: ${loopObserver[i]}');
    print(loopObserverOutput[i]);
  }

  for (var i in finalCommand) {
    var pr = Process.runSync('bash', ['-c', i]);
    print('command: $i');
    print(pr.stdout);
    print(pr.stderr);
  }
}
