/// 默认抓取实现：直接 GET 并剥离 HTML 标签。
library;

import 'dart:async';
import 'package:http/http.dart' as http;
import 'fetcher.dart';

/// 用 `http` 包直连的抓取器。
class HttpFetcher implements WebFetcher {
  HttpFetcher({
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// 单次请求超时。
  final Duration timeout;

  @override
  Future<FetchedPage> fetch(String url, {int maxChars = 20000}) async {
    final http.Response response;
    try {
      response = await _client.get(Uri.parse(url)).timeout(timeout);
    } on TimeoutException {
      throw FetchException('请求超时（${timeout.inSeconds}s）');
    }
    if (response.statusCode != 200) {
      throw FetchException('HTTP ${response.statusCode}');
    }
    final String text = stripHtml(response.body);
    return FetchedPage(
      url: url,
      content: text.length > maxChars ? text.substring(0, maxChars) : text,
      format: FetchedFormat.text,
    );
  }
}

/// 去除 script/style 与标签，解码常见实体并压缩空白。
String stripHtml(String html) {
  final String withoutBlocks = html
      .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
  return withoutBlocks
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'[ \t\r\n]+'), ' ')
      .trim();
}
