import "dart:io";
import "dart:async";
import 'package:args/args.dart';
import 'package:format/format.dart';
import 'package:ansicolor/ansicolor.dart';

class Variable {
  String program;
  List<String> args;
  String template;
  Variable(this.program, this.args, this.template);
}

void main(List<String> args) async {
  var parser = ArgParser(allowTrailingOptions: false);
  parser.addOption('exit_code',
      abbr: 'e', defaultsTo: '0', valueHelp: 'exit code');
  parser.addOption('duration',
      abbr: 'd', defaultsTo: '0', valueHelp: 'duration');
  parser.addFlag('escape');

  var argResults = parser.parse(args);
  var env = Platform.environment;
  var func = {
    "branch": Variable("git", ["rev-parse", "--abbrev-ref", "HEAD"], "({})"),
    "hostname": Variable("hostname", [], "{}"),
  };
  var out1 = {
    "user": env["USER"],
    "path": env["PWD"]!.replaceAll(env["HOME"]!, "~"),
    "exit": argResults["exit_code"],
    "tmux": env["TMUX_PANE"] ?? "",
    "duration": argResults["duration"],
  };
  var out2 = {
    "virtualenv": (env["VIRTUAL_ENV"] ?? "", "({virtualenv})"),
  };
  var line1Template =
      "{user}@{hostname} {tmux} {path} {branch} [{exit}] {duration}ms";
  for (var i in func.keys) {
    var key = i;
    var template = func[key]!.template;
    Process.run(func[key]!.program, func[key]!.args)
        .then((ProcessResult results) {
      if (results.exitCode != 0) {
        out1[key] = "";
      } else {
        out1[key] = template.format(results.stdout.trim());
      }
    });
  }
  var now = DateTime.now();
  await Future.doWhile(() async {
    await Future.delayed(Duration(milliseconds: 5));
    if (now.difference(DateTime.now()).inSeconds > 1) {
      return false;
    }
    for (var i in func.keys) {
      if (out1[i] == null) {
        return true;
      }
    }
    return false;
  }).then((x) {
    print(line1Template.format(out1));
    var line2 = "";
    for(var i in out2.keys){
      var (value, template) = out2[i]!;
      if(value.isNotEmpty){
        line2 += template.format({i: value});
      }

      }
    if (line2.isNotEmpty) {
      if(argResults["escape"]){
        print("\\n");
        }
      print(line2);
    }
  });
}
