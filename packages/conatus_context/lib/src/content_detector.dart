/// 内容类型检测：纯正则 + 结构嗅探，无 I/O，确定性。
///
/// 固定顺序：`git status` → diff → 搜索结果 → 构建日志 → JSON 数组 → 表格 →
/// 源码 → 纯文本。先命中先返回，不做混合内容切分。
library;

import 'dart:convert';

import 'content_kind.dart';
import 'text_lines.dart';

/// 一次检测的结论。
class ContentDetection {
  const ContentDetection(
    this.kind, {
    this.confidence = 0.8,
    this.signals = const <String>[],
  });

  /// 内容类型。
  final ContentKind kind;

  /// 置信度（0..1），仅供调试与遥测。
  final double confidence;

  /// 命中的检测信号。
  final List<String> signals;
}

/// 检测函数签名，便于注入替身。
typedef Detector = ContentDetection Function(String input);

class _Rule {
  const _Rule(this.matches, this.detection);

  final bool Function(String text) matches;
  final ContentDetection detection;
}

/// 检测内容类型。
ContentDetection detectContent(String input) {
  final String text = input.startsWith('\uFEFF') ? input.substring(1) : input;
  if (text.trim().isEmpty) {
    return const ContentDetection(ContentKind.passthrough,
        confidence: 1, signals: <String>['empty']);
  }
  for (final _Rule rule in _rules) {
    if (rule.matches(text)) return rule.detection;
  }
  return const ContentDetection(ContentKind.text);
}

const List<_Rule> _rules = <_Rule>[
  _Rule(
    _looksGitStatus,
    ContentDetection(ContentKind.passthrough,
        confidence: 0.99, signals: <String>['git-status']),
  ),
  _Rule(
    _looksDiff,
    ContentDetection(ContentKind.diff, signals: <String>['diff']),
  ),
  _Rule(
    _looksSearch,
    ContentDetection(ContentKind.searchResults, signals: <String>['grep']),
  ),
  _Rule(
    _looksBuildLog,
    ContentDetection(ContentKind.buildLog, signals: <String>['build-log']),
  ),
  _Rule(
    _looksJsonArray,
    ContentDetection(ContentKind.jsonArray, signals: <String>['json-array']),
  ),
  _Rule(
    _looksTabular,
    ContentDetection(ContentKind.tabular, signals: <String>['table']),
  ),
  _Rule(
    _looksSourceCode,
    ContentDetection(ContentKind.sourceCode,
        confidence: 0.7, signals: <String>['source-code']),
  ),
];

bool _looksGitStatus(String text) {
  final bool header =
      RegExp(r'^(On branch |HEAD detached |nothing to commit)', multiLine: true)
          .hasMatch(text);
  final bool section = RegExp(
          r'^(Changes to be committed|Changes not staged for commit|Untracked files):',
          multiLine: true)
      .hasMatch(text);
  return header && section;
}

bool _looksDiff(String text) {
  int signals = 0;
  if (text.contains('diff --git ')) signals++;
  if (RegExp(r'^--- ', multiLine: true).hasMatch(text)) signals++;
  if (RegExp(r'^\+\+\+ ', multiLine: true).hasMatch(text)) signals++;
  if (RegExp(r'^@@ .* @@', multiLine: true).hasMatch(text)) signals++;
  return signals >= 2;
}

final RegExp _searchLine = RegExp(r'^(\S.*?)[:\-](\d+)[:\-](.*)$');

bool _looksSearch(String text) {
  int matches = 0;
  for (final String line in splitTextLines(text)) {
    final RegExpMatch? match = _searchLine.firstMatch(line);
    if (match != null && !RegExp(r'^\d+$').hasMatch(match.group(1)!)) {
      matches++;
    }
    if (matches >= 3) return true;
  }
  return false;
}

bool _looksBuildLog(String text) {
  if (RegExp(
          r'^(=== FAILURES ===|npm ERR!|error\[E\d+\]|make: \*\*\*|'
          r'Traceback \(most recent call last\)|PASS |FAIL )',
          multiLine: true)
      .hasMatch(text)) {
    return true;
  }
  final List<String> lines = splitTextLines(text);
  if (lines.length < 10) return false;
  final int leveled = lines
      .where((String line) =>
          RegExp(r'(^|\s)(FATAL|ERROR|FAIL|WARNING|WARN|INFO|DEBUG|TRACE)\b')
              .hasMatch(line))
      .length;
  return leveled >= 3;
}

bool _looksJsonArray(String text) {
  final String trimmed = text.trimLeft();
  if (!trimmed.startsWith('[')) return false;
  try {
    final Object? decoded = jsonDecode(trimmed);
    return decoded is List<Object?> && decoded.length >= 3;
  } on FormatException {
    return false;
  }
}

bool _looksTabular(String text) {
  final List<String> lines = splitTextLines(text)
      .where((String line) => line.trim().isNotEmpty)
      .take(20)
      .toList();
  if (lines.length < 3) return false;
  if (lines.first.contains('|') &&
      lines.length > 1 &&
      RegExp(r'^\s*\|?[\s:\-|]+\|').hasMatch(lines[1])) {
    return true;
  }
  for (final String delimiter in <String>[',', '\t', ';']) {
    if (_consistentColumns(lines, delimiter)) return true;
  }
  return false;
}

bool _consistentColumns(List<String> lines, String delimiter) {
  final int expected = lines.first.split(delimiter).length;
  if (expected < 2) return false;
  int same = 0;
  for (final String line in lines) {
    if (line.split(delimiter).length == expected) same++;
  }
  return same / lines.length >= 0.9;
}

bool _looksSourceCode(String text) {
  final List<String> lines = splitTextLines(text)
      .where((String line) => line.trim().isNotEmpty)
      .toList();
  if (lines.length < 3) return false;
  final int indented = lines
      .where((String line) => line.startsWith(' ') || line.startsWith('\t'))
      .length;
  if (indented / lines.length < 0.3) return false;
  int categories = 0;
  if (RegExp(r'\b(class|interface|enum|mixin|abstract)\b').hasMatch(text)) {
    categories++;
  }
  if (RegExp(r'\b(def|func|fn|function|Future|void|int|double|String|bool)\b')
      .hasMatch(text)) {
    categories++;
  }
  if (RegExp(r'\b(import|#include|using|package)\b').hasMatch(text)) {
    categories++;
  }
  if (text.contains('{') && text.contains('}')) categories++;
  return categories >= 2;
}
