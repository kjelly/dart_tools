import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:mis_tools/utils/misc.dart';

Function eq = const ListEquality().equals;

Future<bool> processIsRunning(int pid) async {
  var result = await Process.run('ps', ['-p', pid.toString()]);
  return result.exitCode == 0;
}

class MultiSSH {
  final List<String> _hosts;
  final List<String> _ports;
  final List<String> _sshArgs;
  final List<String> _commands;
  final int _interval;
  late final List<List<int>> _outputs;
  late final List<Process?> _process;
  late final List<int> _retryTimeoutHostList;
  int _currentHostIndex = 0;
  bool _repeatCommandFlag = true;
  late final String _clearString;
  var _checkProcessAliveFlag = false;
  var _finished = false;
  var _initFlag = false;

  MultiSSH(
      this._hosts, this._ports, this._sshArgs, this._commands, this._interval) {
    _outputs = List.generate(_hosts.length, (_) => []);
    _process = List.filled(_hosts.length, null);
    _retryTimeoutHostList = List.filled(_hosts.length, 1);

    if (Platform.isWindows) {
      _clearString = '\x1B[2J\x1B[0f';
    } else {
      _clearString = '\x1B[2J\x1B[3J\x1B[H';
    }

    var index = 0;
    for (final i in _hosts) {
      final _index = index;
      Process.start(
              'ssh',
              [
                '-tt',
                ..._ports
                    .map((i) => ['-R', '$i:localhost:$i'])
                    .expand((i) => i),
                ..._sshArgs,
                i
              ],
              mode: ProcessStartMode.normal)
          .then((p) async {
        setProcessStdoutAndStderr(_index, p);
        _outputs[_index] = <int>[];
      });
      index++;
    }

    if (_commands.isNotEmpty && _interval > 0) {
      Timer.periodic(Duration(seconds: _interval), (timer) {
        if (_finished) {
          timer.cancel();
        }
        if (_repeatCommandFlag) {
          for (final i in _process) {
            for (final c in _commands) {
              i?.stdin.write(c + '\n');
            }
          }
        }
      });
    }
  }

  void setProcessStdoutAndStderr(int _index, Process p) {
    _process[_index] = p;

    final tempStdout = p.stdout;
    tempStdout.listen((data) {
      if (utf8.decode(data).contains(_clearString)) {
        _outputs[_index] = <int>[];
      }
      _outputs[_index].addAll(data);
      if (_index == _currentHostIndex) {
        stdout.add(data);
      }
    });

    final tempStderr = p.stderr;
    tempStderr.listen((data) {
      if (utf8.decode(data).contains(_clearString)) {
        _outputs[_index] = <int>[];
      }
      _outputs[_index].addAll(data);
      if (_index == _currentHostIndex) {
        stderr.add(data);
      }
    });
  }

  Future checkProcessAlive() async {
    if (_checkProcessAliveFlag) {
      await doWhile(() => _checkProcessAliveFlag == false);
      return;
    }
    _checkProcessAliveFlag = true;
    var index = 0;
    while (index < _hosts.length) {
      final _index = index;
      final p = _process[_index];
      if (p != null && !(await processIsRunning(p.pid))) {
        _process[_index] = null;
        await Future.delayed(Duration(seconds: _retryTimeoutHostList[_index]));
        _retryTimeoutHostList[_index] *= 2;
        await Process.start(
                'ssh',
                [
                  '-tt',
                  ..._sshArgs,
                  ..._ports
                      .map((i) => ['-R', '$i:localhost:$i'])
                      .expand((i) => i),
                  _hosts[_index]
                ],
                mode: ProcessStartMode.normal)
            .then((p) async {
          setProcessStdoutAndStderr(_index, p);
        });
      }
      index++;
    }
    _checkProcessAliveFlag = false;
  }

  Future waitForReady() async {
    if (_initFlag) return;
    await doWhile(() => _process.any((p) => p == null));
    _initFlag = true;
  }

  void changeHost([int delta = 1]) {
    _currentHostIndex += delta;
    if (_currentHostIndex >= _hosts.length) {
      _currentHostIndex = 0;
    }
    if (_currentHostIndex < 0) {
      _currentHostIndex = _hosts.length - 1;
    }
    print('\b');
  }

  Future writeAsString(String data) async {
    await waitForReady();
    for (final i in _process) {
      i?.stdin.write(data);
    }
  }

  Future writeAsBytes(List<int> data) async {
    await waitForReady();
    if (eq(data, const [17, 10]) ||
        eq(data, const [17]) ||
        eq(data, const [27, 113]) || // ctrl - q
        eq(data, const [4]) || // ctrl - d
        eq(data, const [27, 91, 54, 126] // page down
            )) {
      changeHost();
      print(Process.runSync("clear", [], runInShell: true).stdout);
      stdout.add(_outputs[_currentHostIndex]);
      return;
    } else if (eq(data, const [27, 91, 53, 126])) {
      // page up
      changeHost(-1);
      print(Process.runSync("clear", [], runInShell: true).stdout);
      stdout.add(_outputs[_currentHostIndex]);
      return;
    } else if (eq(data, const [27, 99])) {
      // alt-c
      data = [3];
    } else if (eq(data, const [3])) {
      return;
    }

    await checkProcessAlive();
    for (final i in _process) {
      i?.stdin.add(data);
    }
  }

  bool toggleRepeat() {
    _repeatCommandFlag = !_repeatCommandFlag;
    return _repeatCommandFlag;
  }

  Future close() async {
    _finished = true;
    for (final i in _process) {
      i?.kill();
    }
  }

  static void clearScreen() {
    if (Platform.isWindows) {
      stdout.write('\x1B[2J\x1B[0f');
    } else {
      stdout.write('\x1B[2J\x1B[3J\x1B[H');
    }
  }
}

Future main(List<String> args) async {
  stdin.lineMode = false;
  stdin.echoMode = false;

  var parser = ArgParser();
  parser.addMultiOption('host', abbr: 'h', defaultsTo: []);
  parser.addMultiOption('port', abbr: 'p', defaultsTo: []);
  parser.addMultiOption('ssh-args', defaultsTo: []);
  parser.addOption('log', defaultsTo: '');
  parser.addMultiOption('command', abbr: 'c', defaultsTo: []);
  parser.addOption('interval', abbr: 'i', defaultsTo: '0');
  final results = parser.parse(args);

  final hostList = results['host'] as List<String>;
  final sshArgs = results['ssh-args'];
  final log = results['log'];
  final commandList = results['command'] as List<String>;
  final interval = int.tryParse(results['interval']) ?? 0;
  final portList = results['port'] as List<String>;

  final instance = MultiSSH(hostList, portList, sshArgs, commandList, interval);
  await instance.waitForReady();
  stdin.listen((data) {
    instance.writeAsBytes(data);
  });
  for (final c in commandList) {
    instance.writeAsString(c + '\n');
  }

  ProcessSignal.sigusr1.watch().listen((signal) async {
    instance.toggleRepeat();
  });
}
