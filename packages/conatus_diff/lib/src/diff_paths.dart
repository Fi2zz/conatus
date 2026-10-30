/// diff 路径的清洗：去掉 `a/` / `b/` 前缀、时间戳与 git 的引号转义。
library;

import 'dart:convert';

/// 去掉 `a/` / `b/` 前缀与 `diff -u` 的制表符时间戳。
String cleanDiffPath(String raw) {
  final int tab = raw.indexOf('\t');
  final String value = _unquote((tab < 0 ? raw : raw.substring(0, tab)).trim());
  if (value.startsWith('a/') || value.startsWith('b/')) {
    return value.substring(2);
  }
  return value;
}

/// 从 `diff --git <old> <new>` 的剩余部分解析两侧路径。
///
/// 支持 git 的引号形式（路径含空格 / 特殊字符时 `"a/x y"`）；普通形式
/// 按空格切两个 token。
List<String> gitDiffPaths(String rest) {
  final List<String> tokens = <String>[];
  int index = 0;
  while (index < rest.length && tokens.length < 2) {
    while (index < rest.length && rest[index] == ' ') {
      index++;
    }
    if (index >= rest.length) break;
    final int start = index;
    if (rest[index] == '"') {
      index = _skipQuoted(rest, index);
    } else {
      while (index < rest.length && rest[index] != ' ') {
        index++;
      }
    }
    tokens.add(rest.substring(start, index));
  }
  return tokens;
}

/// 跳过一段 git 引号路径，返回闭合引号之后的下标。
int _skipQuoted(String value, int start) {
  int index = start + 1;
  while (index < value.length) {
    if (value[index] == '\\') {
      index += 2;
      continue;
    }
    if (value[index] == '"') return index + 1;
    index++;
  }
  return value.length;
}

/// 还原 git 的引号 / 反斜杠转义（`"a/x y"`、`\\`、`\"`、`\t`、`\n`）。
///
/// git 对非 ASCII 路径按 UTF-8 字节做八进制转义（`\346\226\207`）；连续的
/// 八进制转义合并成字节序列再按 UTF-8 解码，避免变成数字垃圾。
String _unquote(String value) {
  if (value.length < 2 || !value.startsWith('"') || !value.endsWith('"')) {
    return value;
  }
  final String body = value.substring(1, value.length - 1);
  final StringBuffer out = StringBuffer();
  int index = 0;
  while (index < body.length) {
    final String char = body[index];
    if (char == '\\' && _octalAt(body, index + 1)) {
      final List<int> bytes = <int>[];
      while (index + 3 < body.length && _octalAt(body, index + 1)) {
        bytes.add(int.parse(body.substring(index + 1, index + 4), radix: 8));
        index += 4;
      }
      out.write(utf8.decode(bytes, allowMalformed: true));
      continue;
    }
    if (char == '\\' && index + 1 < body.length) {
      index++;
      out.write(_unescape(body[index]));
    } else {
      out.write(char);
    }
    index++;
  }
  return out.toString();
}

/// 下标处是否是三个八进制数字（git 的字节转义）。
bool _octalAt(String value, int index) {
  if (index + 3 > value.length) return false;
  for (int i = index; i < index + 3; i++) {
    if (value.codeUnitAt(i) < 0x30 || value.codeUnitAt(i) > 0x37) {
      return false;
    }
  }
  return true;
}

String _unescape(String char) => switch (char) {
      'n' => '\n',
      't' => '\t',
      'r' => '\r',
      _ => char,
    };
