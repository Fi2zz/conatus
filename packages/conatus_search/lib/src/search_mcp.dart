/// 托管 MCP 搜索 provider（免 Key）：直连远程 MCP 端点的 `tools/call`。
///
/// 这类端点（Exa / Parallel 的托管 MCP）接受**免握手的一次性调用**：不用先
/// `initialize`，直接 POST 一条 `tools/call` 就能拿到结果。因此本 provider 不
/// 持有长活连接——`SearchProvider` 没有 dispose 生命周期，长期持有 `McpClient`
/// 会泄漏 socket。
///
/// 两个必须遵守的上游约束：
///
/// * `Accept` 必须含 `text/event-stream`，只发 `application/json` 会被 406 拒绝；
/// * 响应正文通常是 SSE（每帧一条 JSON-RPC 消息），也兼容纯 JSON 形态。
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'search_http.dart';
import 'search_types.dart';

/// 一次搜索在托管端点上需要的全部描述。
class McpSearchProfile {
  const McpSearchProfile({
    required this.name,
    required this.endpoint,
    required this.tool,
    required this.buildArguments,
    required this.decode,
  });

  /// provider 名（如 `'parallel'`）。
  final String name;

  /// 端点 URL（保留字符串形态，便于 profile 用 `const` 声明）。
  final String endpoint;

  /// 要调用的远端工具名（如 `'web_search'`）。
  final String tool;

  /// 把 `(query, limit)` 映射成该工具的 `arguments`。
  final Map<String, Object?> Function(String query, int limit) buildArguments;

  /// 把 `tools/call` 的 `result` 解码成搜索结果。
  final List<SearchResult> Function(Map<String, Object?> result) decode;
}

/// 直连托管 MCP 端点的搜索 provider。
class McpSearchProvider implements SearchProvider {
  McpSearchProvider({
    required this.profile,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _endpoint = Uri.parse(profile.endpoint);

  /// 端点与解码方式。
  final McpSearchProfile profile;

  /// 单次查询超时。
  final Duration timeout;

  final http.Client _client;
  final Uri _endpoint;

  @override
  String get name => profile.name;

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final http.Response response = await sendWithTimeout(
      _client.post(
        _endpoint,
        headers: _headers,
        body: jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': <String, Object?>{
            'name': profile.tool,
            'arguments': profile.buildArguments(query, limit),
          },
        }),
      ),
      timeout: timeout,
      provider: name,
    );
    if (response.statusCode != 200) {
      throw SearchException('$name HTTP ${response.statusCode}');
    }
    final List<SearchResult> results = profile.decode(_resultOf(response.body));
    // 部分端点（如 Parallel）没有条数参数，只能在此截断。
    return results.take(limit).toList(growable: false);
  }

  /// 取出 JSON-RPC 的 `result`，失败一律转成 [SearchException]。
  Map<String, Object?> _resultOf(String body) {
    final Map<String, Object?>? rpc = decodeMcpResponseBody(body);
    if (rpc == null) throw SearchException('$name 返回了无法解析的正文');
    final Object? result = rpc['result'];
    if (result is! Map<String, Object?>) {
      final Object? error = rpc['error'];
      throw SearchException(
        error == null ? '$name 响应缺少 result' : '$name 调用失败：$error',
      );
    }
    if (result['isError'] == true) {
      throw SearchException('$name 工具报错：${mcpResultText(result)}');
    }
    return result;
  }
}

const Map<String, String> _headers = <String, String>{
  'content-type': 'application/json',
  // 缺了 text/event-stream 会被上游以 406 拒绝（实测 Exa 与 Parallel 均如此）。
  'accept': 'application/json, text/event-stream',
};

/// 从响应正文里解出 JSON-RPC 消息：兼容 SSE（多帧取首帧）与纯 JSON。
Map<String, Object?>? decodeMcpResponseBody(String body) {
  final StringBuffer frame = StringBuffer();
  for (final String line in const LineSplitter().convert(body)) {
    if (line.startsWith('data:')) {
      if (frame.isNotEmpty) frame.write('\n');
      frame.write(line.substring(5).trim());
      continue;
    }
    if (line.trim().isNotEmpty || frame.isEmpty) continue;
    final Map<String, Object?>? decoded = _tryMap(frame.toString());
    if (decoded != null) return decoded;
    frame.clear();
  }
  return _tryMap(body.trim());
}

/// `result.structuredContent`；缺失时尝试把 `content` 文本当 JSON 解析。
///
/// 后者用于「只给文本但内容恰好是 JSON」的实现，避免再写一条解析分支。
Map<String, Object?>? mcpStructuredResult(Map<String, Object?> result) {
  final Object? structured = result['structuredContent'];
  if (structured is Map<String, Object?>) return structured;
  final String text = mcpResultText(result);
  return text.isEmpty ? null : _tryMap(text);
}

/// 拼接 `result.content` 里所有文本块。
String mcpResultText(Map<String, Object?> result) {
  final Object? content = result['content'];
  if (content is! List) return '';
  final StringBuffer buffer = StringBuffer();
  for (final Object? block in content) {
    if (block is! Map<String, Object?> || block['text'] is! String) continue;
    if (buffer.isNotEmpty) buffer.write('\n');
    buffer.write(block['text'] as String);
  }
  return buffer.toString();
}

Map<String, Object?>? _tryMap(String raw) {
  if (raw.isEmpty) return null;
  try {
    final Object? decoded = jsonDecode(raw);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}
