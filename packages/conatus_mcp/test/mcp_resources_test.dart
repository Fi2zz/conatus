import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';
import 'fake_transport.dart';
import 'mcp_test_support.dart';

void main() {
  late FakeTransport transport;

  setUp(() {
    transport = FakeTransport();
  });

  McpClient newClient() {
    final McpClient client =
        McpClient(transport: transport, serverName: 'fake');
    addTearDown(client.close);
    return client;
  }

  test('resources/list：按 nextCursor 翻页合并', () async {
    autoRespond(transport, (String method, Map<String, Object?>? params) {
      if (method != 'resources/list') return fakeServerReply(method, params);
      if (params?['cursor'] == null) {
        return <String, Object?>{
          'resources': <Object?>[
            <String, Object?>{'uri': 'file:///a', 'name': 'a'},
          ],
          'nextCursor': 'c2',
        };
      }
      return <String, Object?>{
        'resources': <Object?>[
          <String, Object?>{
            'uri': 'file:///b',
            'name': 'b',
            'description': 'B 资源',
            'mimeType': 'text/plain',
          },
        ],
      };
    });
    final McpClient client = newClient();

    final List<McpResource> resources = await client.listResources();

    expect(
      resources.map((McpResource resource) => resource.uri),
      <String>['file:///a', 'file:///b'],
    );
    expect(resources.last.name, 'b');
    expect(resources.last.description, 'B 资源');
    expect(resources.last.mimeType, 'text/plain');
    expect(
      transport.requests
          .where((McpMessage message) => message.method == 'resources/list')
          .length,
      2,
    );
    expect(transport.requests.last.params, <String, Object?>{'cursor': 'c2'});
  });

  test('resources/templates/list：按 nextCursor 翻页合并', () async {
    autoRespond(transport, (String method, Map<String, Object?>? params) {
      if (method != 'resources/templates/list') {
        return fakeServerReply(method, params);
      }
      if (params?['cursor'] == null) {
        return <String, Object?>{
          'resourceTemplates': <Object?>[
            <String, Object?>{
              'uriTemplate': 'file:///{path}',
              'name': 'file',
            },
          ],
          'nextCursor': 'c2',
        };
      }
      return <String, Object?>{
        'resourceTemplates': <Object?>[
          <String, Object?>{
            'uriTemplate': 'db://{table}/{id}',
            'name': 'row',
            'mimeType': 'application/json',
          },
        ],
      };
    });
    final McpClient client = newClient();

    final List<McpResourceTemplate> templates =
        await client.listResourceTemplates();

    expect(
      templates.map((McpResourceTemplate template) => template.uriTemplate),
      <String>['file:///{path}', 'db://{table}/{id}'],
    );
    expect(templates.last.mimeType, 'application/json');
  });

  test('resources/read：文本内容', () async {
    autoRespond(transport, fakeServerReply);
    final McpClient client = newClient();

    final List<McpResourceContents> contents =
        await client.readResource('file:///a.txt');

    expect(contents.single.uri, 'file:///a.txt');
    expect(contents.single.mimeType, 'text/plain');
    expect(contents.single.text, '你好');
    expect(contents.single.blob, isNull);
    expect(
      transport.requests.single.params,
      <String, Object?>{'uri': 'file:///a.txt'},
    );
  });

  test('resources/read：二进制内容走 blob', () async {
    autoRespond(transport, (String method, Map<String, Object?>? params) {
      if (method != 'resources/read') return fakeServerReply(method, params);
      return <String, Object?>{
        'contents': <Object?>[
          <String, Object?>{
            'uri': 'file:///a.png',
            'mimeType': 'image/png',
            'blob': 'iVBORw0=',
          },
        ],
      };
    });
    final McpClient client = newClient();

    final List<McpResourceContents> contents =
        await client.readResource('file:///a.png');

    expect(contents.single.text, isNull);
    expect(contents.single.blob, 'iVBORw0=');
    expect(contents.single.mimeType, 'image/png');
  });

  test('服务端不支持 resources/*：返回空表且不断连', () async {
    transport.onSend = (McpMessage message) async {
      final Object? id = message.id;
      final String? method = message.method;
      if (id == null || method == null) return;
      if (method.startsWith('resources/')) {
        transport.emit(
          McpMessage(id: id, error: const McpError(-32601, '未实现')),
        );
        return;
      }
      final Map<String, Object?>? result =
          fakeServerReply(method, message.params);
      if (result != null) transport.emit(McpMessage(id: id, result: result));
    };
    final McpClient client = newClient();
    await client.initialize();

    expect(await client.listResources(), isEmpty);
    expect(await client.listResourceTemplates(), isEmpty);
    expect(await client.readResource('file:///a'), isEmpty);
    expect(client.ready, isTrue);
  });
}
