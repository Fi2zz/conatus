/// 默认抓取实现：直接 GET 并剥离 HTML 标签。
library;

import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'fetcher.dart';

/// 用 `http` 包直连的抓取器。
///
/// 覆盖到的失败形态——缺主机名或非 http(s) 的链接、请求超时、非 200 响应、
/// [http.ClientException]（DNS 与连接失败经 `IOClient` 归入此类）以及 `dart:io` 的
/// [IOException] 系（含 TLS 握手失败）——都归一成 [FetchException]，调用方只需捕获
/// 这一种异常。
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
    final Uri? uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw FetchException('仅支持带主机名的 http/https 链接："$url"');
    }
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw FetchException('请求超时（${timeout.inSeconds}s）');
    } on http.ClientException catch (error) {
      throw FetchException('抓取失败：${error.message}');
    } on IOException catch (error) {
      throw FetchException('抓取失败：$error');
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
