import 'dart:io';
import 'dart:math';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:easy_isolate/easy_isolate.dart';
import 'package:args/args.dart';
import 'package:logging/logging.dart';

int prefixRatio(String a, String b) {
  final al = a.length;
  final bl = b.length;
  var index = 0;
  while (index < al && index < bl) {
    if (a[index] != b[index]) {
      break;
    }
    index++;
  }
  return (2 * index * 100) ~/ (al + bl);
}

Future main(List<String> args) async {
  var parser = ArgParser();
  parser.addMultiOption('ignore', abbr: 'i', help: 'ignore words');
  parser.addOption('file', abbr: 'f', help: 'File to read', defaultsTo: '');
  parser.addOption('dict', abbr: 'd', help: 'Dictionary file', defaultsTo: '');
  parser.addOption('start', abbr: 's', help: 'start', defaultsTo: '0');
  parser.addOption('start-column',
      abbr: 'c', help: 'start column', defaultsTo: '0');
  parser.addOption('end', abbr: 'e', help: 'end', defaultsTo: '0');
  parser.addFlag('remove-random',
      abbr: 'r', help: 'remove random words', defaultsTo: false);
  parser.addOption('worker',
      abbr: 'w', help: 'worker', defaultsTo: 'cpu', valueHelp: 'cpu|numbers');
  parser.addOption('threshold',
      abbr: 't', help: 'Threshold for fuzzy matching', defaultsTo: '80');
  parser.addOption('random-threshold',
      abbr: 'a',
      help: 'Threshold for removing random string',
      defaultsTo: '70');
  late ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    print(e.message);
    print(parser.usage);
    exit(1);
  }

  final filePath = results['file'];
  final dictFilePath = results['dict'] ?? '';
  final threshold = int.tryParse(results['threshold']) ?? 80;
  final randomThreshold = int.tryParse(results['random-threshold']) ?? 70;
  final worker = int.tryParse(results['worker']) ?? Platform.numberOfProcessors;
  final removeRandom = results['remove-random'] ?? false;
  final startColumn = int.tryParse(results['start-column']) ?? 0;
  final start = int.tryParse(results['start']) ?? 0;
  final end = int.tryParse(results['end']) ?? 0;
  final ignore = (results['ignore'] ?? [])
      .map((i) => i.trim().toString().toLowerCase())
      .toList();

  var data = <String>[];

  var stripData = <String>[];
  var dict = <String>[];
  if (removeRandom) {
    if (dictFilePath.isEmpty) {
      print('Dictionary file is required');
      exit(1);
    }
    dict = File(dictFilePath).readAsLinesSync();
  }
  dict = dict.map((s) => s.toLowerCase()).toList();
  dict.shuffle();

  var lines = <String>[];
  if (filePath.isEmpty) {
    while (true) {
      var line = stdin.readLineSync();
      if (line == null) break;
      lines.add(line);
    }
  } else {
    lines = File(filePath).readAsLinesSync();
  }

  var remain = lines.length;

  EasyIsolate removeRandomWordIsolate = EasyIsolate((args) {
    RegExp exp = RegExp(r'[a-zA-Z0-9]+');
    RegExp hasDigit = RegExp(r'[0-9]+');
    var line = args[0] as String;
    if (startColumn != 0) {
      line = line.split(' ').sublist(startColumn).join(' ');
    }
    line = line.substring(start, line.length - end).toLowerCase();
    for (var i in ignore) {
      line = line.replaceAll(i, '');
    }
    var stripString = line;
    if (removeRandom) {
      for (var m in exp.allMatches(line)) {
        var matched = m.group(0)!.toLowerCase();
        if (matched.toString().isEmpty) continue;
        if (hasDigit.firstMatch(matched) != null) {
          stripString = stripString.replaceAll(matched, '');
          continue;
        }
        if (matched.length > 10) {
          stripString = stripString.replaceAll(matched, '');
          continue;
        }
        var found = false;
        for (var word in dict) {
          if (ratio(matched, word) > randomThreshold) {
            found = true;
            break;
          }
        }
        if (!found) {
          stripString = stripString.replaceAll(matched, '');
        }
      }
    }
    return stripString;
  }, worker: worker);

  EasyIsolate deRedundantIsolate = EasyIsolate((args) {
    var stripString = args[0] as String;
    var stripData = args[1] as List<String>;
    var threshold = args[2] as int;

    var found = false;
    for (var j in stripData) {
      if (ratio(stripString, j) > threshold) {
        found = true;
        break;
      }
    }
    return found;
  }, worker: worker);

  Stream.fromIterable(lines).listen((oriLine) async {
    String stripString = await removeRandomWordIsolate.call([oriLine]);
    if (!await deRedundantIsolate.call([stripString, stripData, threshold])) {
      data.add(oriLine);
      stripData.add(stripString);
    }

    remain--;
  });

  await Future.doWhile(() async {
    await Future.delayed(Duration(milliseconds: 100));
    return remain > 0;
  });
  for (var i = stripData.length - 1; i >= 0; i--) {
    for (var j = 0; j < i; j++) {
      if (ratio(stripData[i], stripData[j]) > threshold) {
        stripData.removeAt(i);
        data.removeAt(i);
        break;
      }
    }
  }

  await removeRandomWordIsolate.close();
  await deRedundantIsolate.close();

  data.sort();
  for (var i in data) {
    print(i);
  }
  exit(0);
}
