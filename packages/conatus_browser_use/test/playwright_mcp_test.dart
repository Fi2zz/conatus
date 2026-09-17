import 'package:conatus_browser_use/conatus_browser_use.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'support/fake_transport.dart';

Map<String, Object?>? _reply(String method, Map<String, Object?>? params) {
  switch (method) {
    case 'initialize':
      return <String, Object?>{
        'protocolVersion': '2024-11-05',
        'capabilities': <String, Object?>{},
        'serverInfo': <String, Object?>{'name': 'playwright', 'version': '1.0'},
      };
    case 'tools/list':
      return <String, Object?>{
        'tools': <Object?>[
          <String, Object?>{'name': 'browser_navigate'},
          <String, Object?>{'name': 'browser_click'},
        ],
      };
    case 'tools/call':
      return <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'ok from server'},
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
  late List<FakeTransport> transports;
  late PlaywrightMcpProvider provider;

  setUp(() {
    transports = <FakeTransport>[];
    provider = PlaywrightMcpProvider(
      transportFactory: (String command, List<String> args,
              Map<String, String> env) =>
          _transportOf(transports, _reply),
    );
  });

  group('PlaywrightMcpProvider', () {
    test('name 与 serverName 正确', () {
      expect(provider.name, 'playwright');
    });

    test('initializeFor 握手并发现工具，绑定 Session ID', () async {
      final Session session = Session(id: 's1');
      final SessionBrowser browser = await provider.initializeFor(session);

      expect(browser.sessionId, 's1');
      expect(browser.isActive, isTrue);
      expect(browser.toolNames, containsAll(<String>['browser_navigate', 'browser_click']));
      expect(transports, hasLength(1));
      expect(transports.single.connected, isTrue);
    });

    test('同一 Session 跨轮次复用同一浏览器', () async {
      final Session session = Session(id: 's1');
      final SessionBrowser first = await provider.initializeFor(session);
      final SessionBrowser second = await provider.initializeFor(session);

      expect(identical(first, second), isTrue);
      expect(transports, hasLength(1), reason: '复用不应新建客户端');
    });

    test('不同 Session 各建各的浏览器与客户端', () async {
      final SessionBrowser a = await provider.initializeFor(Session(id: 'a'));
      final SessionBrowser b = await provider.initializeFor(Session(id: 'b'));

      expect(a.sessionId, 'a');
      expect(b.sessionId, 'b');
      expect(identical(a, b), isFalse);
      expect(transports, hasLength(2));
    });

    test('call 转发到 tools/call 并映射为 ToolResult', () async {
      final SessionBrowser browser =
          await provider.initializeFor(Session(id: 's1'));
      final ToolResult result = await browser.call('browser_navigate', <String, Object?>{
        'url': 'https://example.com',
      });

      expect(result.isError, isFalse);
      expect(result.content, contains('ok from server'));
      final FakeTransport transport = transports.single;
      final String? toolName =
          transport.sent.lastWhere((m) => m.method == 'tools/call').params?['name'] as String?;
      expect(toolName, 'browser_navigate');
    });

    test('服务端失败结果映射为 ToolResult.failure', () async {
      final FakeTransport failing = FakeTransport();
      autoRespond(failing, (String method, Map<String, Object?>? params) {
        if (method == 'tools/call') {
          return <String, Object?>{
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'server exploded'},
            ],
            'isError': true,
          };
        }
        return _reply(method, params);
      });
      final PlaywrightMcpProvider failingProvider = PlaywrightMcpProvider(
        transportFactory: (String command, List<String> args,
                Map<String, String> env) =>
            failing,
      );
      final SessionBrowser browser =
          await failingProvider.initializeFor(Session(id: 's1'));
      final ToolResult result = await browser.call('browser_navigate', <String, Object?>{});

      expect(result.isError, isTrue);
      expect(result.error?.code, 'MCP_TOOL_ERROR');
    });

    test('release 关闭该 Session 的浏览器与客户端', () async {
      final Session session = Session(id: 's1');
      final SessionBrowser browser = await provider.initializeFor(session);
      await provider.release(session);

      expect(browser.isActive, isFalse);
      expect(transports.single.disconnected, isTrue);
      expect(provider.initializeFor(session), completes,
          reason: '释放后可重新初始化（新建客户端）');
    });

    test('dispose 关闭全部浏览器与客户端', () async {
      await provider.initializeFor(Session(id: 'a'));
      await provider.initializeFor(Session(id: 'b'));
      await provider.dispose();

      expect(transports, hasLength(2));
      for (final FakeTransport transport in transports) {
        expect(transport.disconnected, isTrue);
      }
    });

    test('初始化失败时关闭客户端并传播异常', () async {
      final FakeTransport broken = FakeTransport()
        ..connectError = StateError('cannot launch browser');
      final PlaywrightMcpProvider brokenProvider = PlaywrightMcpProvider(
        transportFactory: (String command, List<String> args,
                Map<String, String> env) =>
            broken,
      );
      await expectLater(
        brokenProvider.initializeFor(Session(id: 's1')),
        throwsStateError,
      );
    });
  });
}
