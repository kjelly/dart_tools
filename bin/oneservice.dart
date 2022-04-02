import 'dart:io';

import 'package:args/args.dart';

Future<Process> run(String command) {
  return Process.start('bash', ['-c', command]);
}

void main(List<String> args) async {
  var parser = ArgParser();
  parser.addFlag('help', abbr: "h", negatable: false);
  parser.addMultiOption('command', abbr: "c", defaultsTo: []);
  parser.addMultiOption('pre-command', abbr: "p", defaultsTo: []);
  parser.addMultiOption('post-command', abbr: "o", defaultsTo: []);
  parser.addMultiOption('pre-wait', abbr: "w", defaultsTo: []);
  parser.addMultiOption('post-wait', abbr: "x", defaultsTo: []);
  parser.addFlag('exit-on-error', abbr: "e", negatable: false);

  List<Process> processes = [];
  late ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    print(e);
    print(parser.usage);
    exit(1);
  }
  var finish = true;
  while (!finish) {
    for (var i in results['pre-command']) {
      var pr = Process.runSync('bash', ['-c', i]);
      stdout.write(pr.stdout);
      stderr.write(pr.stderr);
    }
    for (var i in results['pre-wait']) {
      var pr = Process.runSync('bash', ['-c', i]);
      stdout.write(pr.stdout);
      stderr.write(pr.stderr);
      if (pr.exitCode != 0) {
        finish = false;
      }
    }
    if (!finish && results['exit-on-error']) {
      exit(1);
    }
  }
  for (var i in results['command']) {
    run(i).then((p) {
      p.stdout.listen(stdout.add);
      p.stderr.listen(stderr.add);
      processes.add(p);
    });
  }
  ProcessSignal.sigint.watch().listen((_) async {
    for (var i in processes) {
      i.kill();
    }

    for (var i in processes) {
      await i.exitCode;
    }
    for (var i in results['post-command']) {
      Process.runSync('bash', ['-c', i]);
    }
    for (var i in results['post-wait']) {
      var pr = Process.runSync('bash', ['-c', i]);
      if (pr.exitCode != 0) {
        finish = false;
      }
    }
    exit(0);
  });
}
