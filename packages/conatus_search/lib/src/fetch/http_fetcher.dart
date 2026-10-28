/// 默认抓取实现：直接 GET 并剥离 HTML 标签。
library;

import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'fetcher.dart';
import 'html_markdown.dart';

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
    this.maxBytes = 5 * 1024 * 1024,
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// 单次请求超时。
  final Duration timeout;

  /// 响应体硬上限（字节）；超过即失败，避免把超大文件读进内存。
  final int maxBytes;

  Future<http.Response> _getFollowingRedirects(Uri start) async {
    Uri current = start;
    for (int redirects = 0; redirects <= 10; redirects++) {
      final http.Request request = http.Request('GET', current)
        ..followRedirects = false;
      final http.StreamedResponse streamed =
          await _client.send(request).timeout(timeout);
      final http.Response response = await http.Response.fromStream(streamed);
      final int status = response.statusCode;
      if (status < 300 || status >= 400) return response;
      final String? location = response.headers['location'];
      if (location == null || location.isEmpty) return response;
      if (redirects == 10) throw const FetchException('重定向次数超过 10');
      final Uri next = current.resolve(location);
      if (next.scheme != 'http' && next.scheme != 'https') {
        throw FetchException('重定向到不支持的协议：${next.scheme}');
      }
      current = next;
    }
    throw const FetchException('重定向次数超过 10');
  }

  @override
  Future<FetchedPage> fetch(
    String url, {
    int maxChars = 20000,
    FetchedFormat format = FetchedFormat.text,
  }) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw FetchException('仅支持带主机名的 http/https 链接："$url"');
    }
    final http.Response response;
    try {
      response = await _getFollowingRedirects(uri);
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
    if (response.bodyBytes.length > maxBytes) {
      throw FetchException('响应体超过 $maxBytes 字节上限');
    }
    final String contentType = response.headers['content-type'] ?? '';
    final bool htmlPage = contentType.contains('html') ||
        response.body.contains('<html') ||
        response.body.contains('<p');
    final String content = switch (format) {
      FetchedFormat.html => response.body,
      FetchedFormat.markdown =>
        htmlPage ? htmlToMarkdown(response.body) : response.body,
      FetchedFormat.text =>
        htmlPage ? stripHtml(response.body) : response.body,
    };
    return FetchedPage(
      url: url,
      content: content.length > maxChars
          ? content.substring(0, maxChars)
          : content,
      format: format,
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
