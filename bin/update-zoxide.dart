import "dart:io";

Future<bool> hasZoxidePath(String path) async {
  ProcessResult result = await Process.run("zoxide", ["query", path]);
  return result.exitCode == 0;
}

void addZoxidePath(String path) async {
  ProcessResult result = await Process.run("zoxide", ["add", path]);
}

void main(List<String> args) async {
  var lst = List<String>.from(args) + [Platform.environment['HOME'] ?? ""];
  for (var i in args) {
    if(i == "") continue;
    var dir  = Directory(i);
    dir.watch(events: FileSystemEvent.create).listen((event) async {
      if (event.isDirectory) {
        if (!await hasZoxidePath(event.path)) {
          addZoxidePath(event.path);
        } else {
          print("Already added ${event.path}");
        }
      }
    });
    dir.list(recursive: false).listen((element) async {
      if (element is Directory) {
        if (!await hasZoxidePath(element.path)) {
          addZoxidePath(element.path);
        } else {
          print("Already added ${element.path}");
        }
      }
    });
  }
}
