/// Kimi（Moonshot）抓取后端：调用 `POST /v1/tools/fetch`，返回 markdown 正文。
///
/// 与 [DeepSeekFetcher] 一样是可选后端：在 `provideWebTools` 里需显式传入
/// `backend: FetchBackend.kimi` 才会启用，缺省仍是 [HttpFetcher]。区别只在
/// 字段名——Kimi 的正文放在 `markdown` 而 DeepSeek 放在 `content`；两者都只产出
/// markdown，因此请求 html / text 时同样在 [FetchedPage.format] 上如实标注。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../kimi_shared.dart';
import 'fetcher.dart';

/// 走 Kimi `/v1/tools/fetch` 的抓取器。
///
/// 失败语义与其它抓取器一致：非法链接、请求超时、非 200 响应、
/// [http.ClientException] 与 `dart:io` 的 [IOException] 系（含 TLS 握手失败）
/// 都归一成 [FetchException]。上游 403 `security_risk`（风控拒绝）与
/// 404 `markdown_not_found`（取不到正文）的 `error.message` 会拼进文案，便于判断
/// 该换链接还是该换后端。
class KimiFetcher implements WebFetcher {
  KimiFetcher({
    required this.apiKey,
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 45),
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse('$kKimiBaseUrl/v1/tools/fetch');

  /// Kimi API Key。
  final String apiKey;

  /// 单次请求超时。
  final Duration timeout;

  final http.Client _client;
  final Uri _endpoint;

  @override
  Future<FetchedPage> fetch(
    String url, {
    int maxChars = 20000,
    FetchedFormat format = FetchedFormat.text,
  }) async {
    _validateUrl(url);
    final http.Response response = await _post(url);
    if (response.statusCode != 200) {
      throw FetchException('kimi HTTP ${response.statusCode}'
          '${kimiErrorDetail(response.body)}');
    }
    final String content = _readContent(response.body);
    return FetchedPage(
      url: url,
      content:
          content.length > maxChars ? content.substring(0, maxChars) : content,
      // 上游只给 markdown；不谎报成调用方请求的格式。
      format: FetchedFormat.markdown,
    );
  }

  /// 本地前置拒绝非法链接：上游虽会回 400 `invalid_url`，但没必要为此计费往返。
  void _validateUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw FetchException('仅支持带主机名的 http/https 链接："$url"');
    }
  }

  Future<http.Response> _post(String url) async {
    try {
      return await _client
          .post(
            _endpoint,
            headers: kimiHeaders(apiKey),
            body: jsonEncode(<String, Object?>{'url': url}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw FetchException('kimi 请求超时（${timeout.inSeconds}s）');
    } on http.ClientException catch (error) {
      throw FetchException('抓取失败：${error.message}');
    } on IOException catch (error) {
      throw FetchException('抓取失败：$error');
    }
  }

  String _readContent(String body) {
    final Object? decoded = decodeKimiJson(body);
    if (decoded is! Map<String, Object?>) {
      throw const FetchException('kimi 返回了非对象 JSON');
    }
    final Object? content = decoded['markdown'];
    if (content is String) return content;
    if (content == null) return '';
    throw const FetchException('kimi 返回了非字符串的 markdown');
  }
}
