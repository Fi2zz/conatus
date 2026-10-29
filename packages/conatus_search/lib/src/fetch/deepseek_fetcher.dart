/// DeepSeek 抓取后端：调用 `POST /v1/tools/fetch`，返回 markdown 正文。
///
/// 与 [FirecrawlFetcher] 一样是可选后端：在 `provideWebTools` 里需显式传入
/// 才会启用，缺省仍是 [HttpFetcher]。区别是它只产出 markdown——DeepSeek 的
/// Fetch 接口不做格式选择，因此请求 html / text 时同样返回 markdown，并在
/// [FetchedPage.format] 上如实标注，避免调用方误以为拿到了原始 HTML。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../deepseek_shared.dart';
import 'fetcher.dart';

/// 走 DeepSeek `/v1/tools/fetch` 的抓取器。
///
/// 失败语义与其它抓取器一致：非法链接、请求超时、非 200 响应、
/// [http.ClientException] 与 `dart:io` 的 [IOException] 系（含 TLS 握手失败）
/// 都归一成 [FetchException]。上游 403（安全策略拒绝）与 404（取不到可用正文）
/// 的 `error.message` 会拼进文案，便于判断该换链接还是该换后端。
class DeepSeekFetcher implements WebFetcher {
  DeepSeekFetcher({
    required this.apiKey,
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 45),
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse('$kDeepSeekBaseUrl/v1/tools/fetch');

  /// DeepSeek API Key。
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
      throw FetchException('deepseek HTTP ${response.statusCode}'
          '${deepSeekErrorDetail(response.body)}');
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
            headers: deepSeekHeaders(apiKey),
            body: jsonEncode(<String, Object?>{'url': url}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw FetchException('deepseek 请求超时（${timeout.inSeconds}s）');
    } on http.ClientException catch (error) {
      throw FetchException('抓取失败：${error.message}');
    } on IOException catch (error) {
      throw FetchException('抓取失败：$error');
    }
  }

  String _readContent(String body) {
    final Object? decoded = decodeDeepSeekJson(body);
    if (decoded is! Map<String, Object?>) {
      throw const FetchException('deepseek 返回了非对象 JSON');
    }
    final Object? content = decoded['content'];
    if (content is String) return content;
    if (content == null) return '';
    throw const FetchException('deepseek 返回了非字符串的 content');
  }
}
