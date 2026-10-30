/// 把 `Process.run` 的输出统一成文本 / 原始字节。
///
/// 两种形态都要认：显式 `stdoutEncoding: null` 时是 `List<int>`，否则是
/// `String`。早先只认 `List<int>`，导致 `rev-parse HEAD` 的输出被当成空串，
/// 快照随即以「提交树读取失败」告终。
library;

import 'dart:convert';

/// 取子进程输出为字符串（按 UTF-8，非法字节替换）。
String gitOutputText(Object? raw) {
  if (raw is String) return raw;
  if (raw is! List<int>) return '';
  return const Utf8Decoder(allowMalformed: true).convert(raw);
}

/// 取子进程输出的原始字节（`git show` 读二进制内容用）。
///
/// [gitOutputText] 会把非法 UTF-8 替换成 U+FFFD，二进制经它读出来就毁了。
/// 已是字符串（系统编码）时退回 UTF-8 编码。
List<int> gitOutputBytes(Object? raw) {
  if (raw is List<int>) return raw;
  if (raw is String) return const Utf8Encoder().convert(raw);
  return const <int>[];
}
