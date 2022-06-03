import 'dart:io';
import 'dart:async';
import 'dart:convert';

DateTime? parseTime(String? s) {
  if (s == null) {
    return null;
  }
  DateTime? t;
  try {
    t = DateTime.parse(s);
  } catch (e) {
    var diff = int.tryParse(s);
    if (diff == null) {
      t = null;
    } else {
      t = DateTime.now().subtract(Duration(hours: diff));
    }
  }
  return t;
}

List<String> parseLine(String line) {
  var stack = <String>[];
  var output = <String>[];
  var temp = '';
  for (var i in line.trim().split('')) {
    if (i == ' ') {
      if (stack.isEmpty) {
        output.add(temp);
        temp = '';
      } else {
        temp += i;
      }
    } else if (i == "'") {
      if (stack.isEmpty) {
        stack.add("'");
      } else {
        output.add(temp);
        temp = '';
        stack.removeLast();
      }
    } else {
      temp += i;
    }
  }
  if (temp.isNotEmpty) {
    output.add(temp);
  }
  output = output.where((s) => s.isNotEmpty).toList();
  return output;
}

Future<String> getContentFromCommand(List<String> command) async {
  try {
    var result = await Process.run(
        command[0], command.getRange(1, command.length).toList(),
        runInShell: true);
    if (result.exitCode == 0) {
      var ret = result.stdout as String;
      return ret;
    } else {
      return "failed to get content";
    }
  } catch (e) {
    return Future.value("");
  }
}

Future<String> getContentFromFile(String path) async {
  try {
    var f = File(path);
    if (f.existsSync()) {
      return f.readAsString();
    }
    return Future.value("");
  } catch (e) {
    return Future.value("");
  }
}

bool contains(String text, String pattern, {bool regex = false}) {
  if (regex) {
    return RegExp(pattern).hasMatch(text);
  }
  for (var i in pattern.split('|')) {
    if (text.contains(i)) {
      return true;
    }
  }
  return false;
}

bool containKeys(String s, List<String> keys) {
  for (var i in keys) {
    if (!s.contains(i)) {
      return false;
    }
  }
  return true;
}

List<String> split(String s, int offset) {
  List<String> ret = [];
  var parts = s.split('\n');

  for (var i = 0; i < parts.length; i += offset) {
    if ((i + offset) > parts.length) {
      ret.add(parts.getRange(i, parts.length).join('\n'));
      break;
    }
    ret.add(parts.getRange(i, i + offset).join('\n'));
  }
  return ret;
}

Future<String> fzf(String text, Stream<List<int>> broadcastStdin,
    {flag = const <String>[]}) {
  var completer = Completer<String>();
  Process.start('fzf', flag, mode: ProcessStartMode.normal).then((p) async {
    p.stdin.write(text);
    p.stdin.flush();
    var output = '';
    p.stdout.listen((data) {
      output += utf8.decode(data);
    }, onDone: () {});
    p.stderr.listen(stderr.add, onDone: () {});
    var subscription = broadcastStdin.listen(p.stdin.add, onDone: () {});
    await p.exitCode;
    await subscription.cancel();
    completer.complete(output);
  });
  return completer.future;
}

Future<int> runInShell(String program, List<String> args) async {
  var p = await Process.start(program, args,
      mode: ProcessStartMode.inheritStdio, runInShell: true);
  /* p.stdout.listen(stdout.add);
  p.stderr.listen(stderr.add); */
  return p.exitCode;
}

Future waitForTaskList(List<Future> tasks) async {
  for (final i in tasks) {
    await i;
  }
}

Future doWhile(FutureOr<bool> Function() action) async {
  await Future.doWhile(() async {
    final ret = action();
    await Future.delayed(Duration(milliseconds: 100));
    return ret;
  });
}
