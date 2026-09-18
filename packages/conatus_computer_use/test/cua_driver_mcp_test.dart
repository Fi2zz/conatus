import 'dart:convert';
import 'package:conatus_computer_use/conatus_computer_use.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

import 'support/fake_transport.dart';

Map<String, Object?>? _reply(String method, Map<String, Object?>? params) {
  switch (method) {
    case 'initialize':
      return <String, Object?>{
        'protocolVersion': '2024-11-05',
        'capabilities': <String, Object?>{},
        'serverInfo': <String, Object?>{'name': 'cua-driver', 'version': '1.0'},
      };
    case 'tools/list':
      return <String, Object?>{
        'tools': <Object?>[
          <String, Object?>{'name': 'screen_capture'},
          <String, Object?>{'name': 'mouse_click'},
        ],
      };
    case 'tools/call':
      final String? tool = params?['name'] as String?;
      if (tool == 'screenshot') {
        return <String, Object?>{
          'content': <Object?>[
            <String, Object?>{
              'type': 'image',
              'data': base64Encode(<int>[1, 2, 3, 4]),
              'mimeType': 'image/png',
            },
          ],
          'structuredContent': <String, Object?>{'width': 10, 'height': 10},
        };
      }
      if (tool == 'list_windows') {
        return <String, Object?>{
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'Found 1 window(s).'},
          ],
          'structuredContent': <String, Object?>{
            'windows': <Object?>[
              <String, Object?>{'window_id': 303, 'title': '微信'},
            ],
          },
        };
      }
      if (tool == 'get_window_state') {
        return <String, Object?>{
          'content': <Object?>[
            <String, Object?>{
              'type': 'text',
              'text': List<String>.filled(300, 'tree').join(' '),
            },
          ],
          'structuredContent': <String, Object?>{
            'windows': <Object?>[
              <String, Object?>{'window_id': 1},
            ],
          },
        };
      }
      if (tool == 'launch_app') {
        final Map<String, Object?>? arguments =
            params?['arguments'] as Map<String, Object?>?;
        if (arguments?['fail'] == true) {
          return <String, Object?>{
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'launch failed'},
            ],
            'isError': true,
          };
        }
        if (arguments?['no_pid'] == true) {
          return <String, Object?>{
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'Launched agent app'},
            ],
            'structuredContent': <String, Object?>{
              'bundle_id': 'com.example.agent',
              'name': 'Agent',
            },
          };
        }
        return <String, Object?>{
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'Launched Calculator'},
          ],
          'structuredContent': <String, Object?>{
            'pid': arguments?['front_fail'] == true ? 9999 : 4242,
            'bundle_id': 'com.apple.calculator',
            'name': 'Calculator',
            'windows': <Object?>[
              <String, Object?>{'window_id': 303, 'title': 'Calculator'},
            ],
          },
        };
      }
      if (tool == 'bring_to_front') {
        final Map<String, Object?>? arguments =
            params?['arguments'] as Map<String, Object?>?;
        if (arguments?['pid'] == 9999) {
          return <String, Object?>{
            'content': <Object?>[
              <String, Object?>{
                'type': 'text',
                'text': 'no running application for pid',
              },
            ],
            'isError': true,
          };
        }
      }
      return <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'ok from cua'},
        ],
      };
  }
  return null;
}

FakeTransport _transportOf(
  List<FakeTransport> transports,
  Map<String, Object?>? Function(String, Map<String, Object?>?) reply,
) {
  final FakeTransport transport = FakeTransport();
  autoRespond(transport, reply);
  transports.add(transport);
  return transport;
}

void main() {
  group('CuaDriverMcpProvider', () {
    late List<FakeTransport> transports;
    late CuaDriverMcpProvider provider;

    setUp(() {
      transports = <FakeTransport>[];
      provider = CuaDriverMcpProvider(
        transportFactory: (String command, List<String> args,
                Map<String, String> env) =>
            _transportOf(transports, _reply),
      );
    });

    test('name 正确', () {
      expect(provider.name, 'cua-driver-mcp');
    });

    test('initialize 握手并发现工具', () async {
      final DesktopSession session = await provider.initialize();

      expect(session.tools.map((McpTool tool) => tool.name),
          containsAll(<String>['screen_capture', 'mouse_click']));
      expect(transports, hasLength(1));
      expect(transports.single.connected, isTrue);
    });

    test('initialize 幂等，返回同一会话', () async {
      final DesktopSession first = await provider.initialize();
      final DesktopSession second = await provider.initialize();
      expect(identical(first, second), isTrue);
      expect(transports, hasLength(1));
    });

    test('call 转发到 tools/call 并映射 ToolResult', () async {
      final DesktopSession session = await provider.initialize();
      final ToolResult result =
          await session.call('mouse_click', <String, Object?>{'x': 1, 'y': 2});

      expect(result.isError, isFalse);
      expect(result.content, contains('ok from cua'));
      final FakeTransport transport = transports.single;
      final String? tool =
          transport.sent.lastWhere((m) => m.method == 'tools/call').params?['name'] as String?;
      expect(tool, 'mouse_click');
    });

    test('短摘要结果追加 structuredContent JSON（list_windows 可读窗口 id）', () async {
      final DesktopSession session = await provider.initialize();

      final ToolResult result =
          await session.call('list_windows', <String, Object?>{'pid': 1});

      expect(result.isError, isFalse);
      expect(result.content, contains('Found 1 window(s).'));
      expect(result.content, contains('window_id'));
      expect(result.content, contains('微信'));
    });

    test('长内容结果不追加 structuredContent（避免树 JSON 冗余）', () async {
      final DesktopSession session = await provider.initialize();

      final ToolResult result = await session.call('get_window_state', <String, Object?>{
        'pid': 1,
      });

      expect(result.isError, isFalse);
      expect(result.content, startsWith('tree'));
      expect(result.content, isNot(contains('"windows"')));
    });

    test('capture 提取图像字节与尺寸', () async {
      final DesktopSession session = await provider.initialize();
      final Screenshot shot = await session.capture();

      expect(shot.isEmpty, isFalse);
      expect(shot.bytes, <int>[1, 2, 3, 4]);
      expect(shot.width, 10);
      expect(shot.height, 10);
      expect(shot.mimeType, 'image/png');
      expect(shot.attachmentRef, isNull);
    });

    test('persistent 图像支持 + attachmentStore 时持久化并回填引用', () async {
      final InMemoryAttachmentStore store = InMemoryAttachmentStore();
      final CuaDriverMcpProvider persistent = CuaDriverMcpProvider(
        imageSupport: ImageSupport.persistent,
        attachmentStore: store,
        transportFactory: (String command, List<String> args,
                Map<String, String> env) =>
            _transportOf(transports, _reply),
      );
      final Screenshot shot =
          await (await persistent.initialize()).capture();

      expect(shot.attachmentRef, isNotNull);
      expect(await store.load(shot.attachmentRef!), <int>[1, 2, 3, 4]);
    });

    test('diagnostic 图像支持（缺省）不持久化', () async {
      final InMemoryAttachmentStore store = InMemoryAttachmentStore();
      final CuaDriverMcpProvider diagnostic = CuaDriverMcpProvider(
        attachmentStore: store,
        transportFactory: (String command, List<String> args,
                Map<String, String> env) =>
            _transportOf(transports, _reply),
      );
      final Screenshot shot =
          await (await diagnostic.initialize()).capture();

      expect(shot.attachmentRef, isNull);
      expect(store.refs, isEmpty);
    });

    test('capture 带 region 时转发 region 参数', () async {
      final DesktopSession session = await provider.initialize();
      await session.capture(
          region: const ScreenRegion(x: 0, y: 0, width: 100, height: 100));

      final Map<String, Object?>? args = transports.single.sent
          .lastWhere((m) => m.method == 'tools/call')
          .params?['arguments'] as Map<String, Object?>?;
      expect((args?['region'] as Map)['width'], 100);
    });

    test('启动失败（连接失败）向上传播', () async {
      final FakeTransport broken = FakeTransport()
        ..connectError = StateError('cannot launch cua-driver');
      final CuaDriverMcpProvider brokenProvider = CuaDriverMcpProvider(
        transportFactory: (String command, List<String> args,
                Map<String, String> env) =>
            broken,
      );
      await expectLater(brokenProvider.initialize(), throwsStateError);
    });

    test('断连标记后重连（保留注册由装配层管理）', () async {
      final DesktopSession first = await provider.initialize();
      await transports.single.finish();
      await pumpEventQueue();

      // 断连后再次 initialize 应重建客户端（新传输）
      final DesktopSession second = await provider.initialize();
      expect(identical(first, second), isFalse);
      expect(transports, hasLength(2));
    });

    test('dispose 关闭客户端', () async {
      await provider.initialize();
      await provider.dispose();
      expect(transports.single.disconnected, isTrue);
    });

    group('launch_app 前台化', () {
      List<Object?> toolCallNames(List<McpMessage> messages) => messages
          .where((McpMessage m) => m.method == 'tools/call')
          .map((McpMessage m) => m.params?['name'])
          .toList();

      test('launch_app 成功后自动 bring_to_front 把应用带到前台', () async {
        final DesktopSession session = await provider.initialize();
        final ToolResult result = await session.call('launch_app',
            <String, Object?>{'bundle_id': 'com.apple.calculator'});

        expect(result.isError, isFalse);
        expect(result.content, contains('bring_to_front: ok'));
        expect(toolCallNames(transports.single.sent),
            <Object?>['launch_app', 'bring_to_front']);
        final Map<String, Object?>? bringArgs = transports.single.sent
            .lastWhere((McpMessage m) => m.method == 'tools/call')
            .params?['arguments'] as Map<String, Object?>?;
        expect(bringArgs, <String, Object?>{'pid': 4242});
      });

      test('launch_app 失败时不追加 bring_to_front', () async {
        final DesktopSession session = await provider.initialize();
        final ToolResult result = await session.call('launch_app',
            <String, Object?>{'bundle_id': 'com.apple.calculator', 'fail': true});

        expect(result.isError, isTrue);
        expect(toolCallNames(transports.single.sent), <Object?>['launch_app']);
      });

      test('launch_app 无 pid 时不追加 bring_to_front', () async {
        final DesktopSession session = await provider.initialize();
        final ToolResult result = await session.call('launch_app',
            <String, Object?>{'bundle_id': 'com.example.agent', 'no_pid': true});

        expect(result.isError, isFalse);
        expect(toolCallNames(transports.single.sent), <Object?>['launch_app']);
      });

      test('bring_to_front 失败时合并注明但不判整个操作失败', () async {
        final DesktopSession session = await provider.initialize();
        final ToolResult result = await session.call('launch_app', <String, Object?>{
          'bundle_id': 'com.apple.calculator',
          'front_fail': true,
        });

        expect(result.isError, isFalse);
        expect(result.content, contains('bring_to_front: failed'));
        expect(toolCallNames(transports.single.sent),
            <Object?>['launch_app', 'bring_to_front']);
      });

      test('activateLaunchedApp: false 时不追加 bring_to_front', () async {
        final CuaDriverMcpProvider background = CuaDriverMcpProvider(
          activateLaunchedApp: false,
          transportFactory: (String command, List<String> args,
                  Map<String, String> env) =>
              _transportOf(transports, _reply),
        );
        final DesktopSession session = await background.initialize();
        final ToolResult result = await session.call('launch_app',
            <String, Object?>{'bundle_id': 'com.apple.calculator'});

        expect(result.isError, isFalse);
        expect(toolCallNames(transports.last.sent), <Object?>['launch_app']);
      });
    });
  });
}
