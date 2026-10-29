/// Kimi（Moonshot）搜索 provider（需 API Key）：调用 `POST /v1/tools/search`。
///
/// 鉴权与 Kimi 的模型接口共用 `MOONSHOT_API_KEY`（Bearer），因此已把 Kimi 配成
/// LLM 的用户不需要额外申请凭据。上游按**成功且非空**的请求计费，所以它排在
/// [kDefaultSearchOrder] 里带 Key 源的最后一批，不抢默认位置。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_body.dart';
import 'kimi_shared.dart';
import 'search_http.dart';
import 'search_types.dart';

/// 单次查询的结果数上限（上游限制 1..20）。
const int kKimiSearchMaxCount = 20;

/// 上游 `timeout_seconds` 的上限（秒）。
const int kKimiSearchMaxTimeoutSeconds = 60;

/// 摘要长度上限：上游 `snippet` 通常一两百字符，逐条截断免得个别长摘要撑爆上下文。
const int kKimiSnippetLimit = 600;

/// Kimi 搜索 provider（联网搜索 Basic）。
class KimiSearchProvider implements SearchProvider {
  KimiSearchProvider({
    required this.apiKey,
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse('$kKimiBaseUrl/v1/tools/search');

  /// Kimi API Key。
  final String apiKey;

  /// 单次查询超时。
  final Duration timeout;

  final http.Client _client;
  final Uri _endpoint;

  @override
  String get name => 'kimi';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final http.Response response = await sendWithTimeout(
      _client.post(
        _endpoint,
        headers: kimiHeaders(apiKey),
        body: jsonEncode(<String, Object?>{
          'text_query': query,
          'limit': limit.clamp(1, kKimiSearchMaxCount),
          // 与服务端超时对齐：本地等多久，就让上游也花同样的预算。
          'timeout_seconds': _serverTimeoutSeconds,
          // 默认 false：Basic 的 `text` 是整页正文，单条就可能上千字符；结果展示
          // 只需要摘要，要正文的话该走 `webfetch` 精确取目标页。
          'include_content': false,
        }),
      ),
      timeout: timeout,
      provider: name,
    );
    if (response.statusCode != 200) {
      throw SearchException('kimi HTTP ${response.statusCode}'
          '${kimiErrorDetail(decodeJsonBody(response))}');
    }
    final Object? decoded = decodeKimiJson(decodeJsonBody(response));
    if (decoded is! Map<String, Object?>) {
      throw const SearchException('kimi 返回了非对象 JSON');
    }
    final Object? raw = decoded['search_results'];
    if (raw is! List<Object?>) return const <SearchResult>[];
    return <SearchResult>[
      for (final Object? item in raw)
        if (item is Map<String, Object?>) _toResult(item),
    ];
  }

  int get _serverTimeoutSeconds =>
      timeout.inSeconds.clamp(1, kKimiSearchMaxTimeoutSeconds);

  SearchResult _toResult(Map<String, Object?> item) => SearchResult(
        title: item['title'] as String? ?? '',
        url: item['url'] as String? ?? '',
        snippet: _snippet(item),
      );
}

/// 优先 `snippet`；摘要为空时回退 `text`（`include_content=true` 才有正文）。
String _snippet(Map<String, Object?> item) {
  final String text = switch (item['snippet']) {
    final String snippet when snippet.trim().isNotEmpty => snippet,
    _ => item['text'] as String? ?? '',
  };
  final String trimmed = text.trim();
  if (trimmed.length <= kKimiSnippetLimit) return trimmed;
  return '${trimmed.substring(0, kKimiSnippetLimit)}…';
}
