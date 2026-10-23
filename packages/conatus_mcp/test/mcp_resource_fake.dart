/// 资源 / prompt 假 server 的应答数据与按名字造传输。
library;

import 'dart:convert';

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

/// 每台 server 声明的提示词（alpha 带一个必填 + 一个可选参数）。
const Map<String, List<Map<String, Object?>>> promptsByServer =
    <String, List<Map<String, Object?>>>{
  'alpha': <Map<String, Object?>>[
    <String, Object?>{
      'name': 'review',
      'description': '审查代码',
      'arguments': <Object?>[
        <String, Object?>{'name': 'path', 'required': true},
        <String, Object?>{'name': 'depth'},
      ],
    },
  ],
  'beta': <Map<String, Object?>>[],
};

/// 一台按 [server] 名字应答的假传输。
///
/// [declareResources] / [declarePrompts] 控制握手能力声明，用来验证能力协商
/// 不再无谓地请求未声明的目录。
FakeTransport fakeServer(
  String server, {
  Set<String> failing = const <String>{},
  bool declareResources = true,
  bool declarePrompts = true,
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
      McpMessage(
        id: id,
        result: _resultFor(
          server,
          method,
          message.params,
          declareResources: declareResources,
          declarePrompts: declarePrompts,
        ),
      ),
    );
  };
  return transport;
}

Map<String, Object?> _resultFor(
  String server,
  String method,
  Map<String, Object?>? params, {
  bool declareResources = true,
  bool declarePrompts = true,
}) {
  switch (method) {
    case 'initialize':
      return <String, Object?>{
        'protocolVersion': kMcpProtocolVersion,
        'capabilities': <String, Object?>{
          if (declareResources) 'resources': <String, Object?>{},
          if (declarePrompts) 'prompts': <String, Object?>{},
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
  if (uri.endsWith('/multi')) {
    // 3 字节字符 + 64 KiB（65536 % 3 == 1）：截断点必然落在字符中间。
    return <Map<String, Object?>>[
      <String, Object?>{
        'uri': uri,
        'mimeType': 'text/plain; charset=utf-8',
        'text': '你' * (kMcpResourceContentLimit ~/ 3 + 2),
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
      'text': '$server text',
    },
  ];
}

/// 缺省参数渲染成 `<absent>`，用来区分「没传」与「传了空串」。
String _arg(Map<String, Object?>? params, String key) {
  final Object? arguments = params?['arguments'];
  if (arguments is! Map<String, Object?>) return '<absent>';
  return arguments.containsKey(key) ? '${arguments[key]}' : '<absent>';
}
