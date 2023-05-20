import 'dart:convert';
import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:args/args.dart';
import "package:args/command_runner.dart";
import 'package:cli_repl/cli_repl.dart';
import "package:console/console.dart";
import 'package:dart_console/dart_console.dart' as dart_console;
import 'package:dcache/dcache.dart';
import 'package:mis_tools/utils/misc.dart';
import 'package:mis_tools/utils/system.dart';
import 'package:easy_isolate/easy_isolate.dart';

Future<String> grepDart(String pattern, String text,
    {DateTime? start,
    DateTime? end,
    bool invert = false,
    bool regex = false}) async {
  return await EasyIsolate.run((args) {
    var ret = text.split('\n').where((s) {
      if (invert) {
        return !contains(s, pattern, regex: regex);
      }
      return contains(s, pattern, regex: regex);
    });
    if (start != null || end != null) {
      ret = ret.where((s) {
        DateTime? t;
        var parts = s.split(' ');
        if (parts.length > 1) {
          t = DateTime.tryParse(parts.getRange(0, 2).join(' '));
        }
        if (t == null && parts.isNotEmpty) {
          t = DateTime.tryParse(parts.getRange(0, 1).join(' '));
        }
        if (t == null) {
          return false;
        }
        if (start != null && t.isBefore(start)) {
          return false;
        }
        if (end != null && t.isAfter(end)) {
          return false;
        }
        return true;
      });
    }
    return ret.join('\n');
  }) as String;
}

void main(List<String> args) async {
  var parser = ArgParser();
  parser.addMultiOption('file',
      abbr: "f", help: 'read the content from the files.');
  parser.addMultiOption('command',
      abbr: "c", help: 'read the content from the command.');
  parser.addOption('command-from', help: 'read the content from the command.');
  parser.addOption('file-from', help: 'read the content from the command.');
  parser.addFlag('help', abbr: "h");
  var results = parser.parse(args);
  if (results['help']) {
    print(parser.usage);
    return;
  }

  List<List<String>> commandList = [];
  List<String> fileList = [];

  for (var i in results['command']) {
    commandList.add(i.toString().split(' '));
  }
  for (var i in results['file']) {
    fileList.add(i);
  }

  File f;

  f = File(results['command-from'] ?? "");
  if (await f.exists()) {
    for (var i in f.readAsLinesSync()) {
      commandList.add(i.split(' '));
    }
  }
  f = File(results['file-from'] ?? "");
  if (await f.exists()) {
    fileList.addAll(f.readAsLinesSync());
  }

  Map<String, List<String>> content = {};
  Cache<String, String> cache = SimpleCache(storage: InMemoryStorage(10));
  var register = <String, String>{};

  await handleReload(content, commandList, fileList);

  final console = dart_console.Console();
  /* var repl = Repl(prompt: '>>> ', continuation: '... '); */

  var runner = CommandRunner("dynamic_grep", "dynamic grep")
    ..addCommand(GrepCommand(content, print, cache, register))
    ..addCommand(ListCommand(content, print))
    ..addCommand(AddCmdCommand(commandList))
    ..addCommand(AddFileCommand(fileList))
    ..addCommand(ReloadCommand(content, commandList, fileList, cache));

  final broadcastStdin = stdin.asBroadcastStream();

  while (true) {
    var line = await callFzf('a\nb\n', broadcastStdin);
    print('line $line');
    var command = parseLine(line);
    if (command.isEmpty) {
      print('end');
      break;
    }

    console.writeLine('**************', dart_console.TextAlignment.center);
    console.writeLine('*   Output   *', dart_console.TextAlignment.center);
    console.writeLine('**************', dart_console.TextAlignment.center);

    var t1 = DateTime.now();
    try {
      await runner.run(command);
    } catch (e, tracestack) {
      print('ERROR: $e $tracestack');
    }

    print("time: ${DateTime.now().difference(t1)}");
  }
}

Future<String> doGrep(
    String text, List<String> pattern, List<String> invertPattern,
    {DateTime? startTime, DateTime? endTime, bool regex = false}) async {
  var futureString = Future.value(text);
  for (var p in pattern) {
    futureString = futureString.then((c) {
      return grepDart(p, c, start: startTime, end: endTime, regex: regex);
    });
  }
  for (var p in invertPattern) {
    futureString = futureString.then((c) {
      return grepDart(p, c,
          start: startTime, end: endTime, invert: true, regex: regex);
    });
  }
  for (var p in pattern) {
    futureString = futureString.then((c) {
      return applyColor(c, p, AnsiPen()..red(), regex: regex);
    });
  }
  return futureString;
}

Future handleGrep(
    ArgResults? argResult,
    Map<String, List<String>> content,
    dynamic Function(String) show,
    Cache<String, String> cache,
    Map<String, String> register) async {
  if (argResult == null) {
    return;
  }
  var cacheKeyList = List<String>.from(argResult.arguments);
  cacheKeyList.sort();
  var cacheKey = cacheKeyList.join(' ');

  if (cache.containsKey(cacheKey)) {
    var text = cache.get(cacheKey)!;
    show(text);
    if (argResult['fzf']) {
      /* callFzf(text); */
    }
    return;
  }

  var pattern = argResult.rest;
  var invertPattern = argResult['invert'];
  var keys = argResult['key'];
  var registerKey = argResult['to'];
  var regex = argResult['regex'];

  DateTime? startTime = parseTime(argResult['start']);
  DateTime? endTime = parseTime(argResult['end']);
  var jobs = 0;
  var worker = int.tryParse(argResult['worker']) ?? 1000;
  var greenPen = AnsiPen()..green();
  var line = greenPen('*-----------------*');

  if (pattern.isEmpty) {
    show("Please provide pattern.");
    return;
  }

  if (content.keys.isEmpty) {
    print("No data");
  } else {}

  if (argResult['from'] != "") {
    var c = '';
    if (register.containsKey(argResult['from'])) {
      c = register[argResult['from']]!;
    }
    show(await doGrep(c, pattern, invertPattern,
        startTime: startTime, endTime: endTime, regex: regex));
    return;
  }

  var completeOutput = '';
  for (var i in content.keys) {
    if (!containKeys(i, keys)) {
      continue;
    }
    for (var c in content[i]!) {
      while (jobs > worker) {
        await Future.delayed(Duration(milliseconds: 1));
      }

      jobs += 1;
      var futureString = doGrep(c, pattern, invertPattern,
          startTime: startTime, endTime: endTime, regex: regex);
      futureString.then((c) {
        if (c.isNotEmpty) {
          var output = '''
$line
path: $i
content:
$c
$line
              ''';
          show(output);
          completeOutput += output + '\n';
        }
        jobs -= 1;
      });
    }
  }
  while (jobs > 0) {
    await Future.delayed(Duration(milliseconds: 1));
  }
  cache.set(cacheKey, completeOutput);
  if (registerKey != "") {
    register[registerKey] = completeOutput;
  }
  if (argResult['fzf']) {
    /* callFzf(completeOutput); */
  }
}

Future handleReload(Map<String, List<String>> content,
    List<List<String>> commandList, List<String> fileList,
    {int length = 2000}) async {
  var jobs = 0;
  var offset = length;

  for (var i in commandList) {
    jobs += 1;
    getContentFromCommand(i).then((s) {
      jobs -= 1;
      if (s == 'failed to get content') {
        print('Failed to load. cmd: $i');
      } else {
        content[i.join(' ')] = split(s, offset);
      }
    });
  }
  for (var i in fileList) {
    jobs += 1;
    getContentFromFile(i).then((s) {
      jobs -= 1;
      if (s.isNotEmpty) {
        content[i] = split(s, offset);
      } else {
        print('Failed to load. file: $i');
      }
    });
  }

  var progress = ProgressBar();
  while (jobs > 0) {
    progress.update(
        100 - ((jobs / (commandList.length + fileList.length)) * 100).round());
    await Future.delayed(Duration(milliseconds: 1));
  }
  progress.update(100);
}

Future<String> applyColor(String text, String pattern, AnsiPen pen,
    {bool regex = false}) async {
  return await EasyIsolate.run((args) {
    if (regex) {
      var re = RegExp(pattern);
      var count = 0;
      for (var i in re.allMatches(text)) {
        count += 1;
        text = text.split(i.group(0)!).join(pen(i.group(0)!));
        if (count > 1000) {
          return text;
        }
      }
      return text;
    } else {
      var lst = text.split(pattern);
      return lst.join(pen(pattern));
    }
  }) as String;
}

String grepActorFunction(String argsString) {
  var args = jsonDecode(argsString);
  var text = args['text'] as String;
  var invert = args['invert'] as bool;
  var pattern = args['pattern'] as String;
  var start = args['startTime'] as DateTime?;
  DateTime? end;

  return text.split('\n').where((s) {
    if (invert) {
      return !s.contains(pattern);
    }
    return s.contains(pattern);
  }).where((s) {
    if (start == null && end == null) {
      return true;
    } else if (end == null) {
      DateTime t;
      try {
        t = DateTime.parse(s.split(' ').getRange(0, 2).join(' '));
      } catch (e) {
        return false;
      }
      if (t.isBefore(start!)) {
        return false;
      }
      return true;
    }
    return true;
  }).join('\n');
}

class GrepCommand extends Command {
  @override
  final name = "grep";
  @override
  final description = "grep pattern from source. Use `|` for `or`;";
  Map<String, List<String>> content;
  dynamic Function(String) show;
  Cache<String, String> cache;
  Map<String, String> register;

  GrepCommand(this.content, this.show, this.cache, this.register) {
    argParser.addOption('start',
        abbr: 's', help: "'2019-01-02 13:13:13' or 4 for four hours ago");
    argParser.addOption('end',
        abbr: 'e', help: "'2019-01-02 13:13:13' or 4 for four hours ago");
    argParser.addMultiOption('key', abbr: 'k');
    argParser.addMultiOption('invert', abbr: 'v');
    argParser.addOption('worker', abbr: 'w', defaultsTo: "100");
    argParser.addOption('from',
        abbr: 'f', defaultsTo: "", help: "load data from the register.");
    argParser.addOption('to',
        abbr: 't', defaultsTo: "a", help: "store data into the register.");
    argParser.addFlag('fzf', abbr: 'z', defaultsTo: false);
    argParser.addFlag('regex', abbr: 'r', defaultsTo: false);
  }

  @override
  Future run() async {
    await handleGrep(argResults, content, print, cache, register);
  }
}

class ReloadCommand extends Command {
  @override
  final name = "reload";
  @override
  final description = "reload all source";
  Map<String, List<String>> content;
  List<List<String>> commandList;
  List<String> fileList;
  Cache cache;

  ReloadCommand(this.content, this.commandList, this.fileList, this.cache) {
    argParser.addOption('size', abbr: 's', defaultsTo: "1000");
  }

  @override
  void run() async {
    if (argResults == null) {
      return;
    }
    cache.clear();
    var size = int.tryParse(argResults!['size']) ?? 1000;
    await handleReload(content, commandList, fileList, length: size);
  }
}

class ListCommand extends Command {
  @override
  final name = "list";
  @override
  final description = "list all source";
  Map<String, List<String>> content;
  dynamic Function(String) show;

  ListCommand(this.content, this.show);

  @override
  void run() async {
    for (var i in content.keys) {
      show(i);
    }
  }
}

class AddCmdCommand extends Command {
  @override
  final name = "cmd";
  @override
  final description = "add command to source.";
  List<List<String>> commandList;

  AddCmdCommand(this.commandList);

  @override
  void run() async {
    commandList.add(argResults?.rest ?? []);
  }
}

class AddFileCommand extends Command {
  @override
  final name = "file";
  @override
  final description = "add command to source.";
  List<String> fileList;

  AddFileCommand(this.fileList);

  @override
  void run() async {
    fileList.add(((argResults?.rest) ?? []).join());
  }
}
