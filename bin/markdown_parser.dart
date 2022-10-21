import 'dart:io';
import 'dart:convert';
import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:format/format.dart';
import 'package:intl/intl.dart';

import 'package:markdown/markdown.dart' as md;

class MarkdownSearchResult {
  final int level;
  final List<String> headers;
  final String content;
  final String highlighted;
  MarkdownSearchResult(
      this.level, this.headers, this.content, this.highlighted);

  @override
  String toString() {
    return '$level: ${headers.join(', ')}';
  }
}

class SearchResult extends MarkdownSearchResult {
  final String file;
  SearchResult(int level, List<String> headers, String content, this.file,
      String highlighted)
      : super(level, headers, content, highlighted);

  @override
  String toString() {
    return '$file: ${super.toString()}';
  }
}

class Document {
  final String filePath;
  MarkdownParser? parser;
  Document(this.filePath);
  List<String> tags = [];

  List<String> parseTags(String content) {
    var re = RegExp("^|\\s#\\S+");
    return re.allMatches(content).map((m) {
      var v = m.group(0)!;
      v = v.trim();
      if(v.isNotEmpty && v[0] == "#") return v.substring(1);
      return v;
    }).where((v)=> v.isNotEmpty).toList();
  }

  Future<List<SearchResult>> search(List<String> query, List<String> headers,
      {bool color = false,
      bool regex = false,
      List<String> targetTags = const []}) async {
    if (parser == null) {
      parser = MarkdownParser();
      var data = await File(filePath).readAsString();
      parser?.parse(data);
      tags = parseTags(data);
    }
    if (targetTags.isNotEmpty &&
        !targetTags.map((t) => tags.contains(t)).reduce((a, b) => a && b)) {
      return [];
    }
    return parser!
        .search(query, headers, color: color, regex: regex)
        .map((v) => SearchResult(
            v.level, v.headers, v.content, filePath, v.highlighted))
        .toList();
  }
}

class MarkdownParser implements md.NodeVisitor {
  final currentContent = List.generate(6, (index) => <String, String>{});
  final currentBlockName = <String, String>{};
  final stack = <String>[''];
  var isHeader = false;
  final headerNames = ['h1', 'h2', 'h3', 'h4', 'h5', 'h6'];
  var rawText = '';

  /// parse all lines as Markdown
  void parse(String markdownContent) {
    List<String> lines = markdownContent.split('\n');
    md.Document document = md.Document(encodeHtml: false);
    for (md.Node node in document.parseLines(lines)) {
      node.accept(this);
    }
  }

  // NodeVisitor implementation
  @override
  void visitElementAfter(md.Element element) {
    final tag = element.tag;
    if (headerNames.contains(tag)) {
      isHeader = false;
    }
  }

  @override
  bool visitElementBefore(md.Element element) {
    final tag = element.tag;
    if (headerNames.contains(tag)) {
      var index = int.parse(tag.substring(1));
      while (stack.length < index) {
        stack.add('');
      }
      stack.removeRange(index - 1, stack.length);
      isHeader = true;
    }

    return true;
  }

  @override
  void visitText(md.Text text) {
    if (isHeader) {
      stack.add(text.text);
      return;
    }
    for (var i = stack.length - 1; i < headerNames.length; i++) {
      if (stack.length > i) {
        var value =
            currentContent[i][jsonEncode(stack.sublist(0, i + 1))] ?? '';
        currentContent[i][jsonEncode(stack.sublist(0, i + 1))] =
            value + text.text + '\n';
      }
    }
  }

  List<MarkdownSearchResult> search(List<String> patterns, List<String> headers,
      {bool regex = false, bool color = true}) {
    var ret = <MarkdownSearchResult>[];
    for (var i = 5; i >= 0; i--) {
      var keys = currentContent[i].keys.toList();
      keys = keys.where((key) {
        if (headers.isEmpty) return true;
        var arr = (jsonDecode(key) as List).cast<String>();
        if (headers.length == 1) {
          return arr.contains(headers[0]);
        }
        var index = 0;
        for (var h in headers) {
          index = arr.indexOf(h, index);
          if (index == -1) return false;
        }
        return index != -1;
      }).toList();

      for (var k in keys) {
        var value = currentContent[i][k] as String;
        if (regex) {
          if (patterns.map((p) {
            var reg = RegExp(p, dotAll: true, multiLine: true);
            return reg.hasMatch(value);
          }).reduce((a, b) => a && b)) {
            var highlighted = patterns.map((p) {
              var reg = RegExp(p, dotAll: true, multiLine: true);
              return reg
                  .allMatches(value)
                  .toList()
                  .map((m) => m.group(0) ?? '')
                  .join('\n');
            }).join('\n');
            highlighted = value
                .split('\n')
                .where((line) => patterns
                    .map((p) => RegExp(p, dotAll: true, multiLine: true).hasMatch(line))
                    .reduce((a, b) => a || b))
                .join('\n')
                .trim();

            ret.add(MarkdownSearchResult(
                i, (jsonDecode(k) as List).cast<String>(), value, highlighted));
          }
        } else {
          if (patterns.map((p) => value.contains(p)).reduce((a, b) => a && b)) {
            var highlighted = value
                .split('\n')
                .where((line) => patterns
                    .map((p) => line.contains(p))
                    .reduce((a, b) => a || b))
                .join('\n')
                .trim();
            if (color) {
              for (var p in patterns) {
                highlighted =
                    highlighted.replaceAll(p, '\u001b[31m$p\u001b[0m');
              }
            }
            ret.add(MarkdownSearchResult(
                i, (jsonDecode(k) as List).cast<String>(), value, highlighted));
          }
        }
      }
    }

    return ret;
  }
}

class CounterLock {
  int _count = 0;
  void lock() {
    _count++;
  }

  void unlock() {
    _count--;
  }

  Future wait() async {
    while (_count > 0) {
      await Future.delayed(Duration(milliseconds: 10));
    }
  }
}

Future main(List<String> args) async {
  var parser = ArgParser();
  parser.addFlag('regex', abbr: "r", negatable: false, defaultsTo: false);
  parser.addFlag('color', abbr: "c", negatable: false, defaultsTo: false);
  parser.addOption('dir', abbr: "d", defaultsTo: '.');
  parser.addOption('limit', abbr: "l", defaultsTo: '0');
  parser.addOption('separation', abbr: "s", defaultsTo: '-');
  parser.addOption('sort', defaultsTo: 'file', allowed: ['file', 'header']);
  parser.addOption('format',
      abbr: "f", defaultsTo: 'file: {file}\nheader: {header}\n{content}\n');
  parser.addMultiOption('pattern', abbr: "p", defaultsTo: ['']);
  parser.addMultiOption('header', abbr: "h", defaultsTo: []);
  parser.addMultiOption('tag', abbr: "t", defaultsTo: []);

  var argResults = parser.parse(args);
  var dirPath = argResults['dir'] as String;
  var patterns = argResults['pattern'];
  var headers = argResults['header'] as List<String>;
  var color = argResults['color'] as bool;
  var regex = argResults['regex'] as bool;
  var outputFormat = argResults['format'] as String;
  var separation = argResults['separation'] as String;
  var limit = int.tryParse(argResults['limit'] as String) ?? 0;
  var sortMode = argResults['sort'] as String;
  var tags = argResults['tag'] as List<String>;

  var dir = Directory(dirPath);
  var terminalColumnSize = 128;
  try {
    terminalColumnSize = stdout.terminalColumns;
  } catch (e) {}
  final results = <SearchResult>[];
  final locker = CounterLock();
  dir.list(recursive: true).listen((FileSystemEntity entity) {
    if (entity is File) {
      var file = entity;
      if (!file.path.endsWith('.md')) {
        return;
      }
      locker.lock();
      var document = Document(file.path);
      var query = patterns;
      document.search(query, headers, color: color, regex: regex, targetTags: tags).then((r) {
        results.addAll(r);
        locker.unlock();
      });
    }
  }, onDone: () async {
    await locker.wait();
    results.sort((a, b) => sortMode == 'file'
        ? a.file.compareTo(b.file)
        : a.headers.join("").compareTo(b.headers.join("")));
    if (limit == 0) {
      limit = results.length;
    }
    for (var r in results.sublist(0, limit)) {
      if (r.highlighted.trim() != '') {
        print(outputFormat.format({
              'file': r.file.replaceAll(dirPath, ''),
              'header': r.headers,
              'content': r.highlighted
            }) +
            '\n' +
            separation * terminalColumnSize);
      }
    }
  }, onError: (e) {
    print(e);
  });
}
