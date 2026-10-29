/// DeepSeek 搜索 provider（需 API Key）：调用 `POST /v1/tools/search`。
///
/// 鉴权与 DeepSeek 的模型接口共用 `DEEPSEEK_API_KEY`（Bearer），因此已经把
/// DeepSeek 配成 LLM 的用户不需要额外申请凭据。按请求计费（每 1000 次成功请求
/// $0.75），所以它不在 [kDefaultSearchOrder] 末尾，而是排在带 Key 的付费源里
/// 最简单能复用的位置。
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'deepseek_shared.dart';
import 'search_http.dart';
import 'search_types.dart';

/// 单次查询的结果数上限（上游限制）。
const int kDeepSeekSearchMaxCount = 50;

/// 摘要长度上限：`summary` 通常 600~800 字符，逐条截断以免撑爆上下文。
const int kDeepSeekSnippetLimit = 600;

/// DeepSeek 搜索 provider。
class DeepSeekSearchProvider implements SearchProvider {
  DeepSeekSearchProvider({
    required this.apiKey,
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse('$kDeepSeekBaseUrl/v1/tools/search');

  /// DeepSeek API Key。
  final String apiKey;

  /// 单次查询超时。
  final Duration timeout;

  final http.Client _client;
  final Uri _endpoint;

  @override
  String get name => 'deepseek';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final http.Response response = await sendWithTimeout(
      _client.post(
        _endpoint,
        headers: deepSeekHeaders(apiKey),
        body: jsonEncode(<String, Object?>{
          'query': query,
          'count': limit.clamp(1, kDeepSeekSearchMaxCount),
          // 默认 false：content 是网页正文，单条就可能上千字符；summary 已经
          // 是「给模型阅读」的长摘要，够用且不撑上下文。
          'need_content': false,
        }),
      ),
      timeout: timeout,
      provider: name,
    );
    if (response.statusCode != 200) {
      throw SearchException('deepseek HTTP ${response.statusCode}'
          '${deepSeekErrorDetail(response.body)}');
    }
    final Object? decoded = decodeDeepSeekJson(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const SearchException('deepseek 返回了非对象 JSON');
    }
    final Object? raw = decoded['results'];
    if (raw is! List<Object?>) return const <SearchResult>[];
    return <SearchResult>[
      for (final Object? item in raw)
        if (item is Map<String, Object?>) _toResult(item),
    ];
  }

  SearchResult _toResult(Map<String, Object?> item) => SearchResult(
        title: item['title'] as String? ?? '',
        url: item['url'] as String? ?? '',
        snippet: _snippet(item),
      );
}

/// 优先 `summary`（600~800 字符，面向模型），缺失时回退 `snippet`（~150 字符）。
String _snippet(Map<String, Object?> item) {
  final String text = switch (item['summary']) {
    final String summary when summary.trim().isNotEmpty => summary,
    _ => item['snippet'] as String? ?? '',
  };
  final String trimmed = text.trim();
  if (trimmed.length <= kDeepSeekSnippetLimit) return trimmed;
  return '${trimmed.substring(0, kDeepSeekSnippetLimit)}…';
}
