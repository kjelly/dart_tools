import 'dart:io';
import 'dart:convert';
import 'package:mis_tools/utils/misc.dart';
import 'package:mis_tools/utils/system.dart';
import 'package:args/args.dart';

class Container {
  String image;
  String id;
  String state;
  String status;
  String names;

  Future<Map<String, dynamic>> inspect() async {
    var cmd = 'docker inspect $id';
    var result = await Process.run('bash', ['-c', cmd]);
    var json = jsonDecode(result.stdout);
    return json[0];
  }

  Container(this.image, this.id, this.state, this.status, this.names);
  static Container parse(String raw) {
    var map = jsonDecode(raw);
    return Container(
        map['Image'], map['ID'], map['State'], map['Status'], map['Names']);
  }

  static Future<List<Container>> listContainers() async {
    var result =
        await Process.run('docker', ['ps', '-a', '--format', '{{json .}}']);
    if (result.exitCode != 0) {
      throw Exception('Failed to list containers');
    }
    var lines = result.stdout.split('\n');
    var containers = <Container>[];
    for (var line in lines) {
      if (line.isEmpty) continue;
      print(line);
      containers.add(Container.parse(line));
    }
    return containers;
  }
}

Future<List<String>> listContainers() async {
  var pr = await Process.run('docker', ['ps', '-a']);
  if (pr.exitCode != 0) {
    throw Exception('Failed to list containers');
  }
  var lines = pr.stdout.split('\n');
  return lines.sublist(1);
}

Future<List<String>> listImages() async {
  var pr = await Process.run('docker', ['images']);
  if (pr.exitCode != 0) {
    throw Exception('Failed to list images');
  }
  var lines = pr.stdout.split('\n');
  return lines.sublist(1);
}

Future main(List<String> args) async {
  var parser = ArgParser();
  parser.addOption('command', abbr: 'c', defaultsTo: '');
  parser.addOption('type', abbr: 't', defaultsTo: 'container');
  parser.addFlag('edit',
      abbr: 'e', help: 'edit the command before running', negatable: false);
  parser.addFlag('help', negatable: false);
  var argResults = parser.parse(args);
  if (argResults['help']) {
    print(parser.usage);
    return;
  }
  final command = argResults['command'];
  final type = argResults['type'];
  final containerList = await Container.listContainers();
  print(await listContainers());
}
