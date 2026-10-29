/// HTTP 响应体解码：不依赖 `http` 包的 Latin-1 缺省。
///
/// `http.Response.body` 在没有 `charset` 头时按 ISO-8859-1 解码，中文页面会
/// 变成 `ç»´...` 乱码。API / JSON 按规范一律 UTF-8；HTML 先看响应头，再看
/// `<meta charset>`，最后回落 UTF-8。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// JSON / 文本 API 响应：始终按 UTF-8 解码（非法字节替换为 U+FFFD）。
String decodeJsonBody(http.Response response) =>
    utf8.decode(response.bodyBytes, allowMalformed: true);

/// HTML / 纯文本响应：响应头 charset > `<meta charset>` > UTF-8。
String decodeHtmlBody(http.Response response) {
  final String? header = _charsetOf(response.headers['content-type'] ?? '');
  final String? declared = header ?? _metaCharset(response.bodyBytes);
  final String charset = (declared ?? 'utf-8').toLowerCase();
  if (charset == 'iso-8859-1' ||
      charset == 'latin1' ||
      charset == 'latin-1' ||
      charset == 'us-ascii' ||
      charset == 'ascii') {
    return latin1.decode(response.bodyBytes, allowInvalid: true);
  }
  return utf8.decode(response.bodyBytes, allowMalformed: true);
}

String? _charsetOf(String contentType) {
  final RegExpMatch? match =
      RegExp(r'charset\s*=\s*["'']?([A-Za-z0-9._-]+)').firstMatch(contentType);
  return match?.group(1);
}

/// 从 HTML 头部（前 2KB）嗅探 `<meta charset="...">`。
String? _metaCharset(List<int> bytes) {
  final int end = bytes.length < 2048 ? bytes.length : 2048;
  final String head = latin1.decode(bytes.sublist(0, end), allowInvalid: true);
  final RegExpMatch? match = RegExp(
    r'''<meta[^>]+charset\s*=\s*["']?\s*([A-Za-z0-9._-]+)''',
    caseSensitive: false,
  ).firstMatch(head);
  return match?.group(1);
}
