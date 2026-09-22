/// Firecrawl 抓取后端：把网页转成 markdown（含 JS 渲染与反爬处理）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'fetcher.dart';

/// Firecrawl API Key 的凭据键名。
const String kFirecrawlCredentialKey = 'FIRECRAWL_API_KEY';

/// 走 Firecrawl `/v1/scrape` 的抓取器。
///
/// 与 `HttpFetcher` 同一套失败语义——缺主机名或非 http(s) 的链接、请求超时、非 200
/// 响应、[http.ClientException]（DNS 与连接失败）以及 `dart:io` 的 [IOException] 系
/// （含 TLS 握手失败）——都归一成 [FetchException]，调用方只需捕获这一种异常。
class FirecrawlFetcher implements WebFetcher {
  FirecrawlFetcher({
    required this.apiKey,
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 60),
  })  : _client = client ?? http.Client(),
        _endpoint =
            endpoint ?? Uri.parse('https://api.firecrawl.dev/v1/scrape');

  /// Firecrawl API Key。
  final String apiKey;

  /// 单次请求超时。
  final Duration timeout;

  final http.Client _client;
  final Uri _endpoint;

  @override
  Future<FetchedPage> fetch(String url, {int maxChars = 20000}) async {
    _validateUrl(url);
    final http.Response response = await _scrape(url);
    if (response.statusCode != 200) {
      throw FetchException('Firecrawl HTTP ${response.statusCode}');
    }
    return _parsePage(url, response.body, maxChars);
  }

  void _validateUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw FetchException('仅支持带主机名的 http/https 链接："$url"');
    }
  }

  Future<http.Response> _scrape(String url) async {
    try {
      return await _client
          .post(
            _endpoint,
            headers: <String, String>{
              'content-type': 'application/json',
              'authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(<String, Object?>{
              'url': url,
              'formats': <String>['markdown'],
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw FetchException('Firecrawl 请求超时（${timeout.inSeconds}s）');
    } on http.ClientException catch (error) {
      throw FetchException('抓取失败：${error.message}');
    } on IOException catch (error) {
      throw FetchException('抓取失败：$error');
    }
  }

  FetchedPage _parsePage(String url, String body, int maxChars) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const FetchException('Firecrawl 返回了非对象 JSON');
    }
    if (decoded['success'] == false) {
      throw FetchException('Firecrawl 抓取失败：${decoded['error'] ?? '未知原因'}');
    }
    final Object? data = decoded['data'];
    if (data is! Map<String, Object?>) {
      throw const FetchException('Firecrawl 响应缺少 data');
    }
    final String markdown = data['markdown'] as String? ?? '';
    return FetchedPage(
      url: url,
      content: markdown.length > maxChars
          ? markdown.substring(0, maxChars)
          : markdown,
      format: FetchedFormat.markdown,
    );
  }
}
