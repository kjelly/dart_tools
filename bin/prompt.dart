import "dart:io";
import "dart:async";
import 'package:args/args.dart';

void main(List<String> args) async {
  var parser = ArgParser(allowTrailingOptions: false);
  parser.addOption('exit_code',
      abbr: 'e', defaultsTo: '0', valueHelp: 'exit code');
  parser.addOption('duration',
      abbr: 'd', defaultsTo: '0', valueHelp: 'duration');
  var argResults = parser.parse(args);
  var env = Platform.environment;
  var out = {
    "user": env["USER"],
    "path": env["PWD"]!.replaceAll(env["HOME"]!, "~"),
    "exit": argResults["exit_code"],
    "duration": argResults["duration"],
  };
  Process.run("git", ["rev-parse", "--abbrev-ref", "HEAD"])
      .then((ProcessResult results) {
    if (results.exitCode != 0) {
      out["branch"] = "";
    } else {
      out["branch"] = "(${results.stdout.trim()})";
    }
  });
  Process.run("hostname", []).then((ProcessResult results) {
    out["hostname"] = results.stdout.trim();
  });
  var now = DateTime.now();
  await Future.doWhile(() async {
    await Future.delayed(Duration(milliseconds: 5));
    if (now.difference(DateTime.now()).inSeconds > 1) {
      return false;
    }
    return out["branch"] == null || out["hostname"] == null;
  }).then((_) => print(
      "${out["user"]}@${out["hostname"]} ${out["path"]} "
      "${out["branch"]} [${out['exit']}] ${out['duration']}ms"));
}
