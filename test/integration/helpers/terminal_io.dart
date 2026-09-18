/// 终端输出替身：实现 [IOSink]，收集写入的文本并按行保存，供断言。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

/// 内存终端输出。实现 [IOSink]，供 [CliAskUser] / [ConsoleNotifier] 写入。
class TerminalOutput implements IOSink {
  final StringBuffer _buffer = StringBuffer();
  final List<String> _lines = <String>[];
  final Completer<void> _done = Completer<void>();
  bool _closed = false;
  Encoding _encoding = utf8;

  /// 已收到的完整输出行。
  List<String> get lines => List<String>.unmodifiable(_lines);

  /// 全部输出文本（含未换行的尾部）。
  String get text => _lines.join('\n') + _buffer.toString();

  @override
  Encoding get encoding => _encoding;

  @override
  set encoding(Encoding encoding) => _encoding = encoding;

  @override
  Future<void> get done => _done.future;

  @override
  void write(Object? object) => _append('$object');

  @override
  void writeln([Object? object = '']) => _append('$object\n');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _append(objects.join(separator));

  @override
  void writeCharCode(int charCode) => _append(String.fromCharCode(charCode));

  @override
  Future<void> flush() async {}

  @override
  void add(List<int> data) => _append(utf8.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    // 测试替身不传递错误。
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final List<int> chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_done.isCompleted) _done.complete();
  }

  void _append(String chunk) {
    _buffer.write(chunk);
    final String current = _buffer.toString();
    final int lastNewline = current.lastIndexOf('\n');
    if (lastNewline >= 0) {
      _lines.addAll(current
          .substring(0, lastNewline)
          .split('\n')
          .where((String line) => line.isNotEmpty));
      _buffer.clear();
      _buffer.write(current.substring(lastNewline + 1));
    }
  }

  /// 断言输出包含 [substring]。
  void expectContains(String substring) {
    expect(
      text.contains(substring),
      isTrue,
      reason: '未找到输出: $substring\n实际输出:\n$text',
    );
  }

  /// 断言输出包含 [substring] 且恰好一次。
  void expectContainsOnce(String substring) {
    final int count = _occurrences(substring);
    expect(count, 1, reason: '输出应只包含一次: $substring，实际 $count 次');
  }

  /// 断言输出不包含 [substring]。
  void expectNotContains(String substring) {
    expect(
      text.contains(substring),
      isFalse,
      reason: '不应出现输出: $substring\n实际输出:\n$text',
    );
  }

  int _occurrences(String substring) => text.split(substring).length - 1;
}
