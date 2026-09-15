import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';
import 'fake_transport.dart';
import 'mcp_test_support.dart';

void main() {
  test('握手：接受不同协议版本并补发 initialized 通知', () async {
    final FakeTransport transport = FakeTransport();
    autoRespond(transport, fakeServerReply);
    final McpClient client =
        McpClient(transport: transport, serverName: 'fake');
    addTearDown(client.close);

    final McpServerInfo info = await client.initialize();

    expect(info.protocolVersion, '2024-11-05');
    expect(info.name, 'fake');
    expect(info.version, '9.9');
    expect(client.serverInfo?.name, 'fake');
    expect(client.ready, isTrue);
    expect(transport.connected, isTrue);

    final McpMessage hello = transport.requests.single;
    expect(hello.method, 'initialize');
    expect(hello.params?['protocolVersion'], kMcpProtocolVersion);
    expect(hello.params?['capabilities'], <String, Object?>{});
    final Object? clientInfo = hello.params?['clientInfo'];
    expect((clientInfo! as Map<String, Object?>)['name'], 'conatus');

    final McpMessage note = transport.sent.last;
    expect(note.notification, isTrue);
    expect(note.method, 'notifications/initialized');
  });

  test('listTools：按 nextCursor 翻页合并', () async {
    final FakeTransport transport = FakeTransport();
    autoRespond(transport, (String method, Map<String, Object?>? params) {
      if (method != 'tools/list') return fakeServerReply(method, params);
      if (params?['cursor'] == null) {
        return <String, Object?>{
          'tools': <Object?>[
            <String, Object?>{'name': 'a'},
          ],
          'nextCursor': 'c2',
        };
      }
      return <String, Object?>{
        'tools': <Object?>[
          <String, Object?>{'name': 'b'},
        ],
      };
    });
    final McpClient client =
        McpClient(transport: transport, serverName: 'fake');
    addTearDown(client.close);

    final List<McpTool> tools = await client.listTools();

    expect(tools.map((McpTool tool) => tool.name), <String>['a', 'b']);
    expect(
      transport.requests
          .where((McpMessage m) => m.method == 'tools/list')
          .length,
      2,
    );
    expect(transport.requests.last.params, <String, Object?>{'cursor': 'c2'});
  });

  test('listTools：翻页超过上限抛 too-many-pages', () async {
    final FakeTransport transport = FakeTransport();
    autoRespond(transport, (String method, Map<String, Object?>? params) {
      if (method != 'tools/list') return fakeServerReply(method, params);
      return <String, Object?>{'tools': <Object?>[], 'nextCursor': 'again'};
    });
    final McpClient client =
        McpClient(transport: transport, serverName: 'fake');
    addTearDown(client.close);

    await expectLater(
        client.listTools(), throwsA(mcpFailure('too-many-pages')));
  });

  test('callTool：请求形态与成功结果', () async {
    final FakeTransport transport = FakeTransport();
    autoRespond(transport, (String method, Map<String, Object?>? params) {
      if (method != 'tools/call') return fakeServerReply(method, params);
      return <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'ok'},
        ],
        'structuredContent': <String, Object?>{'echo': 'hi'},
      };
    });
    final McpClient client =
        McpClient(transport: transport, serverName: 'fake');
    addTearDown(client.close);

    final McpToolResult result = await client.callTool(
      'echo',
      <String, Object?>{'text': 'hi'},
    );

    expect(result.failed, isFalse);
    expect(describeMcpContent(result.content), 'ok');
    expect(result.structuredContent, <String, Object?>{'echo': 'hi'});

    final McpMessage call = transport.requests.single;
    expect(call.method, 'tools/call');
    expect(call.params?['name'], 'echo');
    expect(call.params?['arguments'], <String, Object?>{'text': 'hi'});
  });

  test('callTool：isError 结果不抛异常', () async {
    final FakeTransport transport = FakeTransport();
    autoRespond(transport, (String method, Map<String, Object?>? params) {
      if (method != 'tools/call') return fakeServerReply(method, params);
      return <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': '打不开文件'},
        ],
        'isError': true,
      };
    });
    final McpClient client =
        McpClient(transport: transport, serverName: 'fake');
    addTearDown(client.close);

    final McpToolResult result =
        await client.callTool('echo', const <String, Object?>{});

    expect(result.failed, isTrue);
    expect(describeMcpContent(result.content), '打不开文件');
  });

  test('乱序响应按 id 关联', () async {
    final FakeTransport transport = FakeTransport();
    final List<McpMessage> arrived = <McpMessage>[];
    transport.onSend = (McpMessage message) async {
      if (message.request) arrived.add(message);
      if (arrived.length < 2) return;
      for (final McpMessage request in arrived.reversed) {
        transport.emit(
          McpMessage(
            id: request.id,
            result: <String, Object?>{
              'content': <Object?>[],
              'structuredContent': <String, Object?>{
                'arg': request.params?['arguments'],
              },
            },
          ),
        );
      }
    };
    final McpClient client =
        McpClient(transport: transport, serverName: 'fake');
    addTearDown(client.close);

    final Future<McpToolResult> first =
        client.callTool('echo', <String, Object?>{'n': 1});
    final Future<McpToolResult> second =
        client.callTool('echo', <String, Object?>{'n': 2});

    expect((await first).structuredContent?['arg'], <String, Object?>{'n': 1});
    expect((await second).structuredContent?['arg'], <String, Object?>{'n': 2});
  });
}
