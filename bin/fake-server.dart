import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:yaml/yaml.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

class ShellOut {
  String body;
  Map<String, String> env;
  ShellOut(this.body, this.env);
}

Future<ShellOut> run(String command, Map<String, String> env) async {
  var process = await Process.start(command, [], environment: env);
  var stdout = process.stdout;
  var stderr = process.stderr;
  await process.exitCode;
  var stdoutString = await stdout.transform(utf8.decoder).join();
  var stderrString = await stderr.transform(utf8.decoder).join();
  return ShellOut(stdoutString, json.decode(stderrString));
}

Future main() async {
  var config = {};
  _readConfig() {
    config = loadYaml(File('config.yaml').readAsStringSync());
  }

  Timer.periodic(Duration(seconds: 1), (timer) async {
    _readConfig();
  });
  _readConfig();

  var env = Map<String, String>.from(Platform.environment);

  Future<Response> _echoRequest(Request request) async {
    print(config);
    for (var i in config['router']) {
      var v = i;
      var path = i['path'];
      if (path[0] == '/') {
        path = path.substring(1);
      }
      print(request.url.path);
      print(request.method);
      print(v['method']);
      if (path == request.url.path &&
          (v['method'] as YamlList).cast<String>().contains(request.method)) {
        var headers = <String, String>{};
        dynamic body;
        if (v['kind'] == 'json') {
          headers['content-type'] = 'application/json';
        }
        if (v.containsKey('text')) {
          body = v['text'];
        } else if (v.containsKey('json')) {
          body = jsonEncode(v['json']);
        } else if (v.containsKey('shell')) {
          var shellOut = await run(v['shell'], env);
          body = shellOut.body;
          env.addAll(shellOut.env);
        }
        return Response.ok(body, headers: headers);
      }
    }
    return Response.notFound('Not Found');
  }

  var handler = const Pipeline().addHandler(_echoRequest);

  var server = await shelf_io.serve(handler, 'localhost', 8080);
  server.autoCompress = true;

  print('Serving at http://${server.address.host}:${server.port}');
}
