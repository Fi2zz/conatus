/// 集成测试用的最小 MCP server：stdio + 逐行 JSON-RPC。
///
/// 只实现 `initialize` / `tools/list`（一个 `echo` 工具）/ `tools/call`
/// （回显 arguments），用于验证 `StdioTransport` + `McpClient` 的端到端链路。
library;

import 'dart:convert';
import 'dart:io';

const Map<String, Object?> _echoTool = <String, Object?>{
  'name': 'echo',
  'title': '回显',
  'description': '原样回显 arguments',
  'inputSchema': <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'text': <String, Object?>{'type': 'string'},
    },
    'required': <String>['text'],
  },
  'annotations': <String, Object?>{'readOnlyHint': true},
};

const Map<String, Object?> _handshake = <String, Object?>{
  'protocolVersion': '2025-06-18',
  'capabilities': <String, Object?>{
    'tools': <String, Object?>{},
  },
  'serverInfo': <String, Object?>{'name': 'echo', 'version': '0.0.1'},
};

Future<void> main() async {
  final Stream<String> lines =
      stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final String line in lines) {
    final Object? decoded = jsonDecode(line);
    if (decoded is! Map<String, Object?>) continue;
    final Object? id = decoded['id'];
    final Object? method = decoded['method'];
    if (id == null || method is! String) continue; // 通知不需要回应
    stdout.writeln(jsonEncode(_reply(id, method, decoded['params'])));
  }
}

Map<String, Object?> _reply(Object id, String method, Object? params) {
  switch (method) {
    case 'initialize':
      return _ok(id, _handshake);
    case 'tools/list':
      return _ok(id, <String, Object?>{
        'tools': <Object?>[_echoTool]
      });
    case 'tools/call':
      final Map<String, Object?> arguments = _argumentsOf(params);
      return _ok(id, <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': jsonEncode(arguments)},
        ],
        'structuredContent': arguments,
      });
    default:
      return <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{'code': -32601, 'message': '未实现：$method'},
      };
  }
}

Map<String, Object?> _ok(Object id, Map<String, Object?> result) =>
    <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};

Map<String, Object?> _argumentsOf(Object? params) {
  if (params is! Map<String, Object?>) return <String, Object?>{};
  final Object? arguments = params['arguments'];
  return arguments is Map<String, Object?> ? arguments : <String, Object?>{};
}
