import 'dart:io';
import 'dart:convert';
import 'package:mis_tools/utils/misc.dart';
import 'package:args/args.dart';

final kubeDoc = '''
create        Create a resource from a file or from stdin.
expose        Take a replication controller, service, deployment or pod and expose it as a new Kubernetes Service
get           Display one or many resources
edit          Edit a resource on the server
delete        Delete resources by filenames, stdin, resources and names, or by resources and label selector
scale         Set a new size for a Deployment, ReplicaSet or Replication Controller
autoscale     Auto-scale a Deployment, ReplicaSet, StatefulSet, or ReplicationController
cluster-info  Display cluster info
top           Display Resource (CPU/Memory) usage.
cordon        Mark node as unschedulable
uncordon      Mark node as schedulable
drain         Drain node in preparation for maintenance
taint         Update the taints on one or more nodes
describe      Show details of a specific resource or group of resources
logs          Print the logs for a container in a pod
attach        Attach to a running container
exec          Execute a command in a container
port-forward  Forward one or more local ports to a pod
proxy         Run a proxy to the Kubernetes API server
cp            Copy files and directories to and from containers.
debug         Create debugging sessions for troubleshooting workloads and nodes
diff          Diff live version against would-be applied version
apply         Apply a configuration to a resource by filename or stdin
patch         Update field(s) of a resource
replace       Replace a resource by filename or stdin
kustomize     Build a kustomization target from a directory or URL.
label         Update the labels on a resource
annotate      Update the annotations on a resource
''';

class KubeResource {
  String? name;
  String kind;
  String? namespace;
  KubeResource(this.name, this.kind, this.namespace);

  @override
  String toString() {
    return '$namespace $kind/$name';
  }
}

class KubeApiResource {
  String name;
  bool isNamespaced;
  KubeApiResource(this.name, this.isNamespaced);

  @override
  String toString() {
    return '$name/$isNamespaced';
  }
}

KubeResource? parseKubeResource(String line) {
  final List<String> parts = line.trim().split(RegExp(' +'));
  if (parts.isEmpty) {
    return null;
  }
  String? name;
  String? namespace;
  if (parts.length >= 3) {
    name = parts[2].trim();
  }
  if (parts.length >= 2) {
    namespace = parts[1].trim();
  }
  final kind = parts[0].trim();
  if (kind.isEmpty) {
    return null;
  }
  return KubeResource(name, kind, namespace);
}

Future<List<KubeApiResource>> getKubeApiResources() async {
  List<KubeApiResource> resources = <KubeApiResource>[];
  String output = await Process.runSync('kubectl', ['api-resources']).stdout;
  List<String> lines = output.split('\n').sublist(1);
  Set<String> names = <String>{};
  for (final line in lines.map((s) => s.trim()).toSet()) {
    final parts = line.split(RegExp(' +'));
    final name = parts[0].trim();
    if (names.contains(name)) {
      continue;
    }
    if (parts.length == 4) {
      resources
          .add(KubeApiResource(parts[0].trim(), parts[3].trim() == 'true'));
    } else if (parts.length == 5) {
      resources
          .add(KubeApiResource(parts[0].trim(), parts[4].trim() == 'true'));
    }
    names.add(name);
  }
  return resources;
}

Future<String> getKubeAllResources(String namespace, String kind) async {
  if (namespace == '') {
    namespace = '--all-namespaces';
  } else {
    namespace = '--namespace=$namespace';
  }
  final command = '''
kubectl get $kind -o custom-columns=KIND:.kind,NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase $namespace
    ''';
  final result = await Process.run('/bin/bash', ['-c', command]);
  if (result.exitCode != 0) {
    throw Exception('Failed to get all resources');
  }
  return result.stdout.toString().split('\n').sublist(1).join('\n');
}

Future main(List<String> args) async {
  var parser = ArgParser();
  parser.addOption('namesapce', abbr: 'n', defaultsTo: '');
  parser.addOption('command', abbr: 'c', defaultsTo: '');
  parser.addOption('type', abbr: 't', defaultsTo: 'all,node');
  parser.addFlag('edit',
      abbr: 'e', help: 'edit the command before running', negatable: false);
  parser.addFlag('help', negatable: false);
  parser.addFlag('api-resources', negatable: false);
  var argResults = parser.parse(args);
  if (argResults['help']) {
    print(parser.usage);
    return;
  }

  var edit = argResults['edit'];
  String command = argResults['command'] ?? '';
  final namespace = argResults['namesapce'] ?? '';
  final kind = argResults['type'] ?? 'all';
  final apiResources = argResults['api-resources'];

  final broadcastStdin = stdin.asBroadcastStream(
      onListen: (subscription) {}, onCancel: (subscription) {});
  String? resources;
  String extraResources = '';
  Future? task;
  final taskList = <Future>[];
  final kubeApiResources = <KubeApiResource>[KubeApiResource('all', true)];
  var namespaceList = <String>[];
  task = getKubeAllResources(namespace, kind).then((value) async {
    resources = value;
    namespaceList.addAll(resources!
        .split('\n')
        .map((l) => parseKubeResource(l)?.namespace ?? '')
        .toSet()
        .where((i) => !['', '<none>'].contains(i))
        .toList()
        .cast<String>());
    if (kubeApiResources.isEmpty) {
      kubeApiResources.addAll(resources!
          .split('\n')
          .map((l) => parseKubeResource(l)?.kind ?? '')
          .toSet()
          .toList()
          .cast<String>()
          .where((i) => !['', '<none>'].contains(i))
          .map((s) => KubeApiResource(s, true)));
    }
  });
  taskList.add(task);

  if (apiResources) {
    task = getKubeApiResources().then((value) {
      kubeApiResources.clear();
      kubeApiResources.addAll(value);
    });
    taskList.add(task);
  }
  await waitForTaskList(taskList);

  for (final k in kubeApiResources) {
    if (k.isNamespaced) {
      for (final i in namespaceList) {
        extraResources += '${k.name} $i\n';
      }
    } else {
      extraResources += '${k.name}\n';
    }
  }

  if (command.isEmpty) {
    command =
        (await fzf(kubeDoc, broadcastStdin)).split(RegExp(' +')).first.trim();
  }
  if (command.isEmpty) {
    exit(0);
  } else if ([
    'autoscale',
    'exec',
    'cp',
    'patch',
    'label',
    'annotate',
    'scale',
    'debug'
  ].contains(command)) {
    edit = true;
  }
  await doWhile(() => resources == null);
  var fzfFlag = ['-m'];
  if (edit) {
    fzfFlag = [];
  }
  taskList.clear();
  final inheritStdioCommandList = <String>["exec", "edit"];

  for (final line in (await fzf(
          (resources ?? '') + extraResources, broadcastStdin,
          flag: fzfFlag))
      .split('\n')) {
    final target = parseKubeResource(line.trim());
    if (target == null) {
      continue;
    }
    final finalNamespace = target.namespace == null
        ? '--all-namespaces '
        : '-n ${target.namespace} ';
    final finalName =
        target.name == null ? target.kind : '${target.kind}/${target.name}';

    var kubeFullCommand = 'kubectl $finalNamespace $command $finalName';

    var extraArgs = '';
    if (edit) {
      stdout.write(kubeFullCommand);
      extraArgs = stdin.readLineSync() ?? '';
    }
    var mode = ProcessStartMode.normal;

    if (inheritStdioCommandList.contains(command)) {
      mode = ProcessStartMode.inheritStdio;
    }

    task =
        Process.start('bash', ['-c', '$kubeFullCommand $extraArgs'], mode: mode)
            .then((p) {
      if (!inheritStdioCommandList.contains(command)) {
        p.stdout.transform(utf8.decoder).listen(stdout.write);
      }
      p.exitCode.then((code) {});
      return p.exitCode;
    });
    if (inheritStdioCommandList.contains(command)) {
      await task;
    }
    taskList.add(task);
  }
  await waitForTaskList(taskList);
  exit(0);
}
