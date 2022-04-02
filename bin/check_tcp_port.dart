import 'dart:io';
import 'dart:convert';
import 'package:args/args.dart';

Future main(List<String> args) async {
  var parser = ArgParser();
  parser.addMultiOption('data', abbr: 'd', defaultsTo: []);
  parser.addOption('host', abbr: 'h', defaultsTo: 'localhost');
  parser.addOption('port', abbr: 'p', defaultsTo: '8888');
  parser.addFlag('listen', abbr: 'l', defaultsTo: false);
  parser.addFlag('utf8', defaultsTo: false);
  var results = parser.parse(args);
  final host = results['host'];
  final port = int.tryParse(results['port']) ?? 8888;
  final listen = results['listen'];
  final utf8DecodeFlag = results['utf8'];
  final data = results['data'];

  Socket.connect(host, port).then((socket) async {
    print('connected');
    if (utf8DecodeFlag) {
      socket.cast<List<int>>().transform(utf8.decoder).listen(print);
    } else {
      socket.listen((data) {
        print(
            data.map((int i) => i.toRadixString(16).padLeft(2, '0')).toList());
      });
    }
    for (final i in data) {
      socket.write(i);
    }
    if (!listen) {
      await Future.delayed(Duration(milliseconds: 100));
      exit(0);
    }
  });
}
