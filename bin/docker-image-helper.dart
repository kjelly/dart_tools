import "dart:io";
import 'package:args/args.dart';

Future<String> shell(String command) async {
  var result = await Process.run("bash", ["-c", command]);
  return (result.stdout) as String;
}

Future<String> docker(List<String> command) async {
  var result = await Process.run("docker", command);
  if (result.exitCode != 0) {
    print("${result.stdout}");
    print("${result.stderr}");
  }
  return (result.stdout) as String;
}

Future<void> dockerPull(String name) async {
  await docker(['pull', name]);
}

Future<void> dockerSave(String name, String filePath) async {
  dockerPull(name);
  await docker(['save', name, '-o', filePath]);
}

Future<void> dockerTag(String oldName, String newName) async {
  await docker(['tag', oldName, newName]);
}

Future<void> dockerPush(String name) async {
  await docker(['push', name]);
}

Future<void> dockerLoad(String path) async {
  await docker(['load', '-i', path]);
}

Future<void> dockerRemoveImage(String name) async {
  await docker(['rmi', name]);
}

Future<void> deliveryImage(String host, String name) async {
  var result =
      await Process.run("bash", ['-c', 'cat $name|ssh $host sudo docker load']);
  if (result.exitCode != 0) {
    print("failed to delivery image, $name.");
    print("stderr: ${result.stderr}");
    print("stdout: ${result.stdout}");
  }
}

String imageToPath(String name) {
  name = name.replaceAll(":", "_");
  name = name.replaceAll("/", ".");
  name = name + '.tar';
  return name;
}

void main(List<String> args) async {
  var parser = new ArgParser();
  parser.addFlag('save',
      abbr: 's', negatable: false, help: "save the image to the file.");
  parser.addFlag('pull', negatable: false, help: "pull images.");
  parser.addFlag('load',
      abbr: 'l', negatable: false, help: "load the images from the files.");
  parser.addFlag('help', negatable: false, help: 'show help.');
  parser.addFlag('remove', negatable: false, help: 'remove the images');
  parser.addOption('delivery',
      abbr: 'd',
      help: "send the images to the hosts by ssh.",
      valueHelp: "the file which contains the hosts");
  parser.addOption('push',
      abbr: 'p',
      help: "push the images to the registry.",
      valueHelp: "registry");
  parser.addOption('tag',
      abbr: 't', help: "change the image tags.", valueHelp: "the new tag");
  parser.addOption('worker',
      abbr: 'w', help: "worker", valueHelp: "worker number", defaultsTo: "5");

  var results = parser.parse(args);
  if (results.rest.length == 0 || results['help']) {
    print(parser.usage);
  }

  var hosts = <String>[];
  var worker = int.tryParse(results['worker'] ?? "5") ?? 5;

  if (results['delivery'] != null) {
    hosts += await File(results['delivery']).readAsLinesSync();
  }

  var jobs = 0;

  for (var fileName in results.rest) {
    var imageList = await File(fileName).readAsLines();
    for (var imageName in imageList) {
      jobs += 1;
      handle(imageName, results, hosts).then((s){
        jobs -= 1;
      });
    }
  }
}

Future<void> handle(String imageName, ArgResults results, List<String> hosts) async {
  var registryRegex = RegExp('[\\w]+\\.[\\w.]+');
  if (results['load'] == true) {
    await dockerLoad(imageToPath(imageName));
  }
  if (results['pull'] == true) {
    await dockerPull(imageName);
  }
  if (results['tag'] != null) {
    var parts = imageName.split(':');
    var newImageName = "";
    if (parts.length > 1) {
      newImageName =
          parts.getRange(0, parts.length - 1).join(":") + ":" + results['tag'];
    } else {
      newImageName = imageName + ":" + results['tag'];
    }
    await dockerTag(imageName, newImageName);
    imageName = newImageName;
  }
  if (results['save']) {
    dockerSave(imageName, imageToPath(imageName)).then((v) async {
      if (results['delivery'] != null) {
        for (var h in hosts) {
          deliveryImage(h, imageToPath(imageName));
        }
      }
    });
  }

  if (results['push'] != null) {
    var oldRegistry = registryRegex.firstMatch(imageName)?.group(0) ?? "";
    var newImageName = imageName.replaceAll(oldRegistry + '/', "");
    newImageName = results['push'] + '/' + newImageName;
    dockerTag(imageName, newImageName).then((v) {
      dockerPush(newImageName);
    });
  }
  if (results['remove'] == true) {
    dockerRemoveImage(imageName);
  }
}
