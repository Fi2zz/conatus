/// 资源 / prompt 测试共用：两台假 server（alpha 文本、beta 二进制）与装配入口。
library;

import 'dart:convert';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_mcp/conatus_mcp.dart';

import 'fake_transport.dart';

/// 每台 server 声明的资源。
const Map<String, List<Map<String, Object?>>> resourcesByServer =
    <String, List<Map<String, Object?>>>{
  'alpha': <Map<String, Object?>>[
    <String, Object?>{
      'uri': 'file:///a',
      'name': 'a.txt',
      'mimeType': 'text/plain',
    },
  ],
  'beta': <Map<String, Object?>>[
    <String, Object?>{'uri': 'file:///b', 'name': 'b.txt'},
  ],
};

/// 每台 server 声明的提示词（alpha 带两个位置参数）。
const Map<String, List<Map<String, Object?>>> promptsByServer =
    <String, List<Map<String, Object?>>>{
  'alpha': <Map<String, Object?>>[
    <String, Object?>{
      'name': 'review',
      'description': '审查代码',
      'arguments': <Object?>[
        <String, Object?>{'name': 'path'},
        <String, Object?>{'name': 'depth'},
      ],
    },
  ],
  'beta': <Map<String, Object?>>[],
};

/// 装配 alpha / beta 两台假 server。
///
/// [failingServer] 的 [failingMethods] 回 JSON-RPC 错误（其余照常应答），
/// 用来验证「单台失败不影响其他 server」。
Future<McpRegistry> bootResourceRegistry(
  Context ctx, {
  String? failingServer,
  Set<String> failingMethods = const <String>{},
}) =>
    provideMcp(
      ctx,
      <McpServerConfig>[
        McpServerConfig(
          name: 'alpha',
          type: McpTransportType.stdio,
          command: 'x',
        ),
        McpServerConfig(
          name: 'beta',
          type: McpTransportType.stdio,
          command: 'x',
        ),
      ],
      transportFactory: (McpServerConfig config) => fakeServer(
        config.name,
        failing:
            config.name == failingServer ? failingMethods : const <String>{},
      ),
    );

/// 一台按 [server] 名字应答的假传输。
FakeTransport fakeServer(
  String server, {
  Set<String> failing = const <String>{},
}) {
  final FakeTransport transport = FakeTransport();
  transport.onSend = (McpMessage message) async {
    final Object? id = message.id;
    final String? method = message.method;
    if (id == null || method == null) return;
    if (failing.contains(method)) {
      transport.emit(
        McpMessage(id: id, error: const McpError(-32603, 'boom')),
      );
      return;
    }
    transport.emit(
      McpMessage(id: id, result: _resultFor(server, method, message.params)),
    );
  };
  return transport;
}

Map<String, Object?> _resultFor(
  String server,
  String method,
  Map<String, Object?>? params,
) {
  switch (method) {
    case 'initialize':
      return <String, Object?>{
        'protocolVersion': kMcpProtocolVersion,
        'capabilities': <String, Object?>{
          'resources': <String, Object?>{},
          'prompts': <String, Object?>{},
        },
        'serverInfo': <String, Object?>{'name': server},
      };
    case 'resources/list':
      return <String, Object?>{
        'resources': resourcesByServer[server] ?? const <Object?>[],
      };
    case 'resources/read':
      return <String, Object?>{
        'contents': _contentsFor(server, '${params?['uri']}'),
      };
    case 'prompts/list':
      return <String, Object?>{
        'prompts': promptsByServer[server] ?? const <Object?>[],
      };
    case 'prompts/get':
      return <String, Object?>{
        'messages': <Object?>[
          <String, Object?>{
            'role': 'user',
            'content': <String, Object?>{
              'type': 'text',
              'text': 'path=${_arg(params, 'path')};'
                  'depth=${_arg(params, 'depth')}',
            },
          },
        ],
      };
  }
  return <String, Object?>{'tools': <Object?>[]};
}

List<Map<String, Object?>> _contentsFor(String server, String uri) {
  if (uri.endsWith('/big')) {
    return <Map<String, Object?>>[
      <String, Object?>{
        'uri': uri,
        'mimeType': 'text/plain',
        'text': 'x' * (kMcpResourceContentLimit + 10),
      },
    ];
  }
  if (uri.endsWith('/bin')) {
    return <Map<String, Object?>>[
      <String, Object?>{
        'uri': uri,
        'mimeType': 'application/octet-stream',
        'blob': base64Encode(<int>[1, 2, 3]),
      },
    ];
  }
  return <Map<String, Object?>>[
    <String, Object?>{
      'uri': uri,
      'mimeType': 'text/plain',
      'text': '$server text'
    },
  ];
}

String _arg(Map<String, Object?>? params, String key) {
  final Object? arguments = params?['arguments'];
  return arguments is Map<String, Object?> ? '${arguments[key] ?? ''}' : '';
}

/// 装配注册表并注册资源工具（供工具用例使用）。
Future<McpRegistry> bootToolRegistry(Context ctx) async {
  final McpRegistry registry = await bootResourceRegistry(ctx);
  provideMcpResourceTools(ctx, registry: registry);
  return registry;
}
