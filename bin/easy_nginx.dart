import 'dart:io';
import 'dart:convert';
import 'package:args/args.dart';
import 'package:tuple/tuple.dart';

Tuple2<String, String> split(String i) {
  final s = i.toString();
  final pos = s.indexOf('=');
  return Tuple2(s.substring(0, pos), s.substring(pos + 1));
}

Future<String> getRealPath(String path) async {
  var pr = await Process.run('bash', ['-c', 'readlink -f "$path"']);
  return pr.stdout.toString().trim();
}

void main(List<String> args) async {
  var parser = ArgParser();
  parser.addOption('port',
      abbr: 'p', help: '', valueHelp: '', defaultsTo: '8888');
  parser.addMultiOption('reverse', abbr: 'r', help: '', valueHelp: '');
  parser.addMultiOption('static', abbr: 's', help: '', valueHelp: '');
  parser.addMultiOption('host', abbr: 'h', help: '', valueHelp: '');
  parser.addFlag('hosts', help: 'mount /etc/hosts');
  parser.addFlag('help');
  var argResults = parser.parse(args);
  if (argResults['help']) {
    print(parser.usage);
    return;
  }
  var dir = Directory.systemTemp.createTempSync();
  var nginxConfPath = '${dir.path}/nginx.conf';
  nginxConfPath = '/tmp/nginx.conf';

  var port = argResults['port'];
  var dockerArgs = [
    'run',
    '--rm',
    '-p',
    '$port:80',
    '-v',
    '$nginxConfPath:/etc/nginx/nginx.conf',
  ];
  if (argResults['hosts']) {
    dockerArgs.addAll(['-v', '/etc/hosts:/etc/hosts']);
  }
  for (var i in argResults['host']) {
    final t = split(i);
    final hostname = t.item1;
    final address = t.item2;
    dockerArgs.addAll(['--add-host', '$hostname:$address']);
  }
  var locations = '';
  for (var i in argResults['reverse']) {
    final t = split(i);
    final path = t.item1;
    final host = t.item2;
    locations += '''
    location $path {
      proxy_pass '$host$path';
      proxy_ssl_verify              off;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
    }
    ''';
  }
  for (var i in argResults['static']) {
    final t = split(i);
    final path = t.item1;
    var filePath = t.item2;
    print(await getRealPath(filePath));
    filePath = Directory(await getRealPath(filePath)).absolute.path;
    /* filePath = Directory(filePath).absolute.path; */
    locations += '''
      location $path {
         root   /var/www;
         autoindex on;
         index  index.html index.htm;
      }
    ''';
    dockerArgs.addAll(['-v', '$filePath:/var/www/$path']);
  }

  var servers = '''
user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
	worker_connections 768;
}

http {

	sendfile on;
	tcp_nopush on;
	tcp_nodelay on;
	keepalive_timeout 65;
	types_hash_max_size 2048;
	include /etc/nginx/mime.types;
	default_type application/octet-stream;

  proxy_cache_path /tmp/nginx/ levels=1:2 keys_zone=nextcloud:100m max_size=1g
                   inactive=1220m use_temp_path=off;

    server {
    listen              0.0.0.0:80;
    $locations
    }
}
  ''';

  print(locations);
  File(nginxConfPath)
    ..createSync()
    ..writeAsString(servers);
  print(nginxConfPath);

  dockerArgs.add('nginx');
  print(dockerArgs);
  Process.start('docker', dockerArgs).then((p) {
    p.stdout.transform(utf8.decoder).forEach(print);
    p.stderr.transform(utf8.decoder).forEach(print);
    ProcessSignal.sigint.watch().listen((signal) async {
      p.kill();
      await p.exitCode;
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
      exit(0);
    });
  });
}
