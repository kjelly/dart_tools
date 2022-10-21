import 'dart:io';
import 'dart:async';
import 'dart:convert';

List<dynamic> findJsonPath(dynamic data, String key, dynamic value){
  var ret = <dynamic>[];
  if(data is int){
    return [];
  }else if(data is String){
    return [];
  }else if(data is bool){
    return [];
  }else if(data is List){
    var i = 0;
    for(i=0;i<data.length;i++){
      var path = findJsonPath(data[i], key, value);
      if(path.isNotEmpty) {
        ret.add(i);
        ret.addAll(path);
        return ret;
        }
    }
  }else if(data is Map){
    if(data.containsKey(key) && data[key] == value){
      return [key];
    }
    for(var k in data.keys){
      var path = findJsonPath(data[k], key, value);
      if(path.isNotEmpty) {
        ret.add(k);
        ret.addAll(path);
        return ret;
        }
    }
  }
  return [];
}

int getWindowId1() {
  var pr = Process.runSync('bash', ['-c',
    'i3-msg -t get_tree']);
  var dct = jsonDecode(pr.stdout);
  var data  = findJsonPath(dct, 'focused', true);
  if (data.isEmpty) {
    return 0;
  }

  for(var i in data.sublist(0, data.length - 3)){
    if(i is int){
      dct = dct[i];
    }
    else if(i != 'focused'){
      dct = dct[i];
    }
  }
  if (dct['layout'] != 'tabbed') {
    return 0;
  }

  return data[data.length - 2] as int;
}


Future main() async {
  var running = false;
  Timer? t;
  void moveWindow()async{
    if(running) return;
    running = true;
    while(getWindowId1() > 0){
      Process.runSync('i3-msg', ['move', 'left']);
    }
    running = false;
    t = null;
  }
    ProcessSignal.sigint.watch().listen((_) {
      print('get signal');
      exit(0);
    });
    ProcessSignal.sigint.watch().listen((_) {
      print('get signal');
      exit(0);
    });

  Process.start('i3-msg', ['-t', 'subscribe', '-m', '["window"]'], runInShell: true).then((Process p) {
    p.kill();
    p.stdout.listen((data)async{
      if(t != null) t?.cancel();
      t = Timer(Duration(milliseconds: 600), moveWindow);
    });
    p.stderr.listen((data) => {});
    stdin.listen((data) => p.stdin.add(data));
  });
  ProcessSignal.sighup.watch().listen((_) {
    print('get signal');
    exit(0);
  });
}
