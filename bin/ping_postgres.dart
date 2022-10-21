import 'package:postgres/postgres.dart';
import 'package:args/args.dart';

void main(List<String> args) async {
  var parser = ArgParser();
  parser.addOption('host');
  parser.addOption('port');
  parser.addOption('database');
  parser.addOption('username');
  parser.addOption('password');
  var results = parser.parse(args);

  final host = results['host'] ?? 'localhost';
  final port = int.parse(results['port'] ?? '5432');
  final database = results['database'] ?? 'postgres';
  final username = results['username'] ?? 'postgres';
  final password = results['password'] ?? '';
  var sequence = 1;

  while (true) {
    final sequenceString = sequence.toStringAsFixed(10);
    try {
      var connection = PostgreSQLConnection(host, port, database,
          username: username, password: password);
      await connection.open();
      await connection.execute('select 1;');
      await connection.close();

      var now = DateTime.now().toUtc();
      final sequenceString = sequence.toString().padLeft(5);
      print('$now seq: $sequenceString : ok');
    } catch (e) {
      var now = DateTime.now().toUtc();
      print('$now seq: $sequenceString : $e');
    }
    sequence++;
    await Future.delayed(Duration(seconds: 1));
  }
}
