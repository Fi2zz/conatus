/// `McpClient` 的协议层读取：工具 / 资源 / 提示词的发现与读取。
///
/// 列表方法复用同一套 `nextCursor` 翻页；服务端回 JSON-RPC `-32601`
/// （方法未实现）时返回空表，而不是断连。
library;

import 'mcp_client_result.dart';
import 'mcp_json.dart';
import 'mcp_prompt_types.dart';
import 'mcp_protocol.dart';
import 'mcp_protocol_tool.dart';
import 'mcp_resource_types.dart';
import 'mcp_types.dart';

/// 单次翻页上限；防服务端异常导致死循环。
const int _maxPages = 20;

/// 发一条请求并等响应；由 [McpClient] 注入。
typedef McpRequestFn = Future<McpMessage> Function(
    String method, Map<String, Object?>? params);

/// 协议层读取器：把方法名、分页与结果解析收在一处。
class McpClientCatalog {
  /// 构造；[request] 由持有连接的客户端提供。
  McpClientCatalog(this._request);

  final McpRequestFn _request;

  /// `tools/list`：全部工具。
  Future<List<McpTool>> tools() => _paged(
        method: 'tools/list',
        field: 'tools',
        parse: McpTool.fromJson,
      );

  /// `resources/list`：全部资源。
  Future<List<McpResource>> resources() => _paged(
        method: 'resources/list',
        field: 'resources',
        parse: McpResource.fromJson,
      );

  /// `resources/templates/list`：全部资源模板。
  Future<List<McpResourceTemplate>> resourceTemplates() => _paged(
        method: 'resources/templates/list',
        field: 'resourceTemplates',
        parse: McpResourceTemplate.fromJson,
      );

  /// `resources/read`：读取一个 URI 的内容块。
  Future<List<McpResourceContents>> readResource(String uri) async {
    final Map<String, Object?>? result = mcpOptionalResult(
      await _request('resources/read', <String, Object?>{'uri': uri}),
    );
    return _items(result, 'contents', McpResourceContents.fromJson);
  }

  /// `prompts/list`：全部提示词模板。
  Future<List<McpPrompt>> prompts() => _paged(
        method: 'prompts/list',
        field: 'prompts',
        parse: McpPrompt.fromJson,
      );

  /// `prompts/get`：用 [arguments] 填充模板，返回消息。
  Future<List<McpPromptMessage>> getPrompt(
    String name, {
    Map<String, String> arguments = const <String, String>{},
  }) async {
    final Map<String, Object?>? result = mcpOptionalResult(
      await _request('prompts/get', <String, Object?>{
        'name': name,
        if (arguments.isNotEmpty) 'arguments': arguments,
      }),
    );
    return _items(result, 'messages', McpPromptMessage.fromJson);
  }

  Future<List<T>> _paged<T>({
    required String method,
    required String field,
    required T Function(Map<String, Object?>) parse,
  }) async {
    final List<T> items = <T>[];
    String? cursor;
    for (int page = 0; page < _maxPages; page++) {
      final Map<String, Object?>? result = mcpOptionalResult(
        await _request(method, _cursorParams(cursor)),
      );
      if (result == null) return items;
      items.addAll(_items(result, field, parse));
      cursor = mcpString(result['nextCursor']);
      if (cursor == null) return items;
    }
    throw McpException('too-many-pages', '$method 翻页超过 $_maxPages 页仍未结束');
  }
}

/// 从 `result[field]` 取出对象列表；`result` 为 `null`（方法未实现）时为空表。
List<T> _items<T>(
  Map<String, Object?>? result,
  String field,
  T Function(Map<String, Object?>) parse,
) {
  if (result == null) return <T>[];
  return <T>[
    for (final Object? item in mcpList(result[field]))
      if (item is Map<String, Object?>) parse(item),
  ];
}

Map<String, Object?>? _cursorParams(String? cursor) =>
    cursor == null ? null : <String, Object?>{'cursor': cursor};
