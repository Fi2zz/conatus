/// 测试共用的假 server 应答与断言助手（传输替身见 fake_transport.dart）。
library;

import 'dart:async';
import 'dart:convert';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';
import 'fake_transport.dart';

/// 单条 JSON 响应正文的响应头。
const Map<String, String> jsonHeaders = <String, String>{
  'content-type': 'application/json; charset=utf-8',
};

/// `text/event-stream` 正文的响应头。
const Map<String, String> sseHeaders = <String, String>{
  'content-type': 'text/event-stream; charset=utf-8',
};

/// 一条 JSON-RPC 成功响应的 JSON 文本。
String jsonRpcResponse(Object id, Map<String, Object?> result) =>
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    });

/// 一段 SSE 帧：可选 `event:` 行 + `data:` 行 + 派发用的空行。
String sseFrame(String data, {String? event}) =>
    '${event == null ? '' : 'event: $event\n'}data: $data\n\n';

/// 测试看护：一条传输 + 它 `messages` 上的消息、流错误与结束信号。
///
/// `messages` 是单订阅流，一条用例只该有一个听者——本类就是那个听者。
class TransportWatch<T extends McpTransport> {
  /// 开始看护 [transport]。
  TransportWatch(this.transport) {
    _subscription = transport.messages.listen(
      messages.add,
      onError: (Object error) {
        failures.add(error);
      },
      onDone: () {
        if (!closed.isCompleted) closed.complete();
      },
    );
  }

  /// 被看护的传输。
  final T transport;

  /// 收到的消息。
  final List<McpMessage> messages = <McpMessage>[];

  /// `messages` 上的流错误（连接级故障）。
  final List<Object> failures = <Object>[];

  /// `messages` 关闭（done）时完成。
  final Completer<void> closed = Completer<void>();

  late final StreamSubscription<McpMessage> _subscription;

  /// 撤销监听。
  Future<void> stop() => _subscription.cancel();
}

/// 通用假 server 应答：握手 + 单页工具 / 资源 / 提示词表 + 空成功结果。
///
/// 返回 `null` 的方法不回应（请求留在待办里），供断连 / 超时用例使用。
Map<String, Object?>? fakeServerReply(
  String method,
  Map<String, Object?>? params,
) =>
    _fakeReplies[method]?.call(params);

final Map<String, Map<String, Object?> Function(Map<String, Object?>?)>
    _fakeReplies =
    <String, Map<String, Object?> Function(Map<String, Object?>?)>{
  'initialize': (_) => <String, Object?>{
        'protocolVersion': '2024-11-05',
        'capabilities': <String, Object?>{},
        'serverInfo': <String, Object?>{'name': 'fake', 'version': '9.9'},
      },
  'tools/list': (_) => <String, Object?>{
        'tools': <Object?>[
          <String, Object?>{
            'name': 'echo',
            'description': '回显',
            'inputSchema': <String, Object?>{'type': 'object'},
          },
        ],
      },
  'tools/call': (_) => <String, Object?>{'content': <Object?>[]},
  'resources/list': (_) => <String, Object?>{
        'resources': <Object?>[
          <String, Object?>{
            'uri': 'file:///fake.txt',
            'name': 'fake.txt',
            'mimeType': 'text/plain',
          },
        ],
      },
  'resources/templates/list': (_) => <String, Object?>{
        'resourceTemplates': <Object?>[
          <String, Object?>{
            'uriTemplate': 'file:///{path}',
            'name': 'file',
          },
        ],
      },
  'resources/read': (Map<String, Object?>? params) => <String, Object?>{
        'contents': <Object?>[
          <String, Object?>{
            'uri': params?['uri'] ?? 'file:///fake.txt',
            'mimeType': 'text/plain',
            'text': '你好',
          },
        ],
      },
  'prompts/list': (_) => <String, Object?>{
        'prompts': <Object?>[
          <String, Object?>{
            'name': 'review',
            'description': '审查代码',
            'arguments': <Object?>[
              <String, Object?>{'name': 'path', 'required': true},
            ],
          },
        ],
      },
  'prompts/get': (Map<String, Object?>? params) => <String, Object?>{
        'description': '审查代码',
        'messages': <Object?>[
          <String, Object?>{
            'role': 'user',
            'content': <String, Object?>{
              'type': 'text',
              'text': 'Review ${_argumentOf(params, 'path')}',
            },
          },
        ],
      },
};

String _argumentOf(Map<String, Object?>? params, String key) {
  final Object? arguments = params?['arguments'];
  if (arguments is! Map<String, Object?>) return '';
  return '${arguments[key] ?? ''}';
}

/// 按 server 名造假传输，并记录装配时收到的配置。
class FakeMcpServers {
  final Map<String, FakeTransport> transports = <String, FakeTransport>{};
  final Map<String, McpServerConfig> configs = <String, McpServerConfig>{};

  FakeTransport build(McpServerConfig config) {
    configs[config.name] = config;
    final FakeTransport transport = FakeTransport();
    transports[config.name] = transport;
    autoRespond(transport, (String method, Map<String, Object?>? params) {
      if (method == 'initialize') {
        return <String, Object?>{
          'protocolVersion': kMcpProtocolVersion,
          'serverInfo': <String, Object?>{'name': config.name},
        };
      }
      if (method == 'tools/list') {
        return <String, Object?>{
          'tools': <Object?>[
            <String, Object?>{
              'name': 'read_file',
              'description': '${config.name} 的 read_file',
            },
          ],
        };
      }
      return <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': '${config.name}:ok'},
        ],
      };
    });
    return transport;
  }
}

/// 立刻挂上监听并等出 [McpException]；避免「先失败后 await」被判为未处理异常。
Future<McpException> failureOf(Future<McpToolResult> call) async {
  try {
    await call;
  } on McpException catch (error) {
    return error;
  }
  fail('期望调用失败，但它成功了');
}

/// 匹配错误码为 [code] 的 [McpException]。
Matcher mcpFailure(String code) =>
    isA<McpException>().having((McpException e) => e.code, 'code', code);
