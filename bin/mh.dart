import 'dart:io';
import 'dart:async';

import 'package:args/args.dart';


class ProcessResultWrapper {


}

Map<String, String> parseDecorator(String input) {
  // finall all patterns like @retry=3 or @ignore
  var reg = RegExp(r'(@([a-zA-Z0-9_]+)=?([a-zA-Z0-9_]*))+');
  var allMatch = reg.allMatches(input);
  var result = <String, String>{};
  for(var match in allMatch) {
    result[match.group(2) ?? ''] = match.group(3) ?? '';
  }
  return result;
}

Future<ProcessResult> ssh(String host, String command) async{
  var comment = '';
  var parts = command.split('#');
  if (parts.length > 1 && !parts[1].contains('"') && !parts[1].contains('\'')) {
    comment = parts[1];
    command = parts[0];
  }

  // retry, wait_for, timeout, ignore, sleep, periodic
  var decorator = parseDecorator(comment);
  var sleepValue = decorator['sleep'];
  if(sleepValue != null) {
    await Future.delayed(Duration(seconds: int.parse(sleepValue)));
  }
  var pr = Process.run('ssh', [host, 'bash', '-c', '"$command"'],
      runInShell: true);



  return pr;
}

void main(List<String> args) async {
  print(parseDecorator('@retry=3 @wait=5'));
  var parser = ArgParser();
  parser.addMultiOption('host', abbr: "h", help: 'host');
  parser.addOption('file',
      abbr: "f", help: 'the host list', valueHelp: '<file>');

  var result = parser.parse(args);
  var commands = result.rest;
  var hosts = result['host'];
  var hostFile = result['file'];
  if (hostFile != null) {
    var lines = await File(hostFile).readAsLines();
    hosts.addAll(lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList());
  }
  if (hosts.isEmpty) {
    print('no host');
    exit(1);
  }
  for (var i in hosts) {
    var _host = i;
    var fpr = Future<ProcessResult>.value(ProcessResult(0, 0, [], []));
    String? oldCommand;
    for (var c in commands) {
      var privateCommand = c;
      var privateOldCommand = oldCommand;
      var errorMessage = '';
      fpr = fpr.then((pr) {
        if (pr.exitCode != 0) {
          errorMessage = '❌';
        }
        if (pr.pid != 0 && privateOldCommand != null) {
          print('$_host(${pr.exitCode}) $errorMessage: $privateOldCommand');
          print('${pr.stdout}');
          print('${pr.stderr}');
        }
        if (pr.exitCode != 0 && pr.pid != 0) {
          exit(1);
        }
        return Process.run('ssh', [i, 'bash', '-c', '"$privateCommand"'],
            runInShell: true);
      });
      oldCommand = privateCommand;
    }
    var errorMessage = '';
    fpr.then((pr) {
      if (pr.exitCode != 0) {
        errorMessage = '❌';
      }
      print(
          '$i(${pr.exitCode}) $errorMessage: ${commands[commands.length - 1]}');
      print('${pr.stdout}');
      print('${pr.stderr}');
    });
  }
}
