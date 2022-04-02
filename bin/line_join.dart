import 'dart:io';
import 'dart:convert';
import 'package:args/args.dart';

Future main(List<String> args) async {
  var parser = ArgParser();
  parser.addFlag('help', abbr: "h", negatable: false);
  parser.addOption('separate',
      abbr: "s", help: 'separate the output.', defaultsTo: " ");
  parser.addOption('mode', abbr: "m", help: 'mode1 or mode2.', mandatory: true);
  parser.addOption('file', abbr: "f", help: 'file path', mandatory: true);
  parser.addOption('number', abbr: "n", help: 'number', defaultsTo: '2');
  var argResults = parser.parse(args);
  final mode = argResults['mode'];
  final num = int.tryParse(argResults['number']) ?? 2;
  final file = argResults['file'];
  var data = File(file).readAsStringSync().trim();
  var lines = data.split('\n');

  if (mode == 'helf') {
    var offset = lines.length ~/ num;
    for (var i = 0; i < offset; i++) {
      var newLine = '';
      for (var j = 0; j < num; j++) {
        newLine += lines[i + j * offset] + ' ';
      }
      print(newLine);
    }
  } else if (mode == 'next') {
    for (var i = 0; i < lines.length; i += num) {
      var newLine = '';
      for (var j = 0; j < num; j++) {
        if ((i + j) > lines.length - 1) break;
        newLine += lines[i + j] + ' ';
      }
      print(newLine);
    }
  }
}
