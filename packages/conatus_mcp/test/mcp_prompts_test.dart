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

  test('prompts/list：按 nextCursor 翻页并解析参数', () async {
    autoRespond(transport, (String method, Map<String, Object?>? params) {
      if (method != 'prompts/list') return fakeServerReply(method, params);
      if (params?['cursor'] == null) {
        return <String, Object?>{
          'prompts': <Object?>[
            <String, Object?>{'name': 'review'},
          ],
          'nextCursor': 'c2',
        };
      }
      return <String, Object?>{
        'prompts': <Object?>[
          <String, Object?>{
            'name': 'explain',
            'description': '解释一段代码',
            'arguments': <Object?>[
              <String, Object?>{
                'name': 'path',
                'description': '文件路径',
                'required': true,
              },
            ],
          },
        ],
      };
    });
    final McpClient client = newClient();

    final List<McpPrompt> prompts = await client.listPrompts();

    expect(
      prompts.map((McpPrompt prompt) => prompt.name),
      <String>['review', 'explain'],
    );
    final McpPromptArgument argument = prompts.last.arguments.single;
    expect(prompts.last.description, '解释一段代码');
    expect(argument.name, 'path');
    expect(argument.description, '文件路径');
    expect(argument.required, isTrue);
    expect(transport.requests.last.params, <String, Object?>{'cursor': 'c2'});
  });

  test('prompts/get：带上参数并取回文本消息', () async {
    autoRespond(transport, fakeServerReply);
    final McpClient client = newClient();

    final List<McpPromptMessage> messages = await client.getPrompt(
      'review',
      arguments: <String, String>{'path': 'a'},
    );

    expect(messages.single.role, 'user');
    expect(messages.single.text, 'Review a');
    expect(
      transport.requests.single.params,
      <String, Object?>{
        'name': 'review',
        'arguments': <String, String>{'path': 'a'},
      },
    );
  });

  test('prompts/get：非文本内容渲染为 [mimeType]', () async {
    autoRespond(transport, (String method, Map<String, Object?>? params) {
      if (method != 'prompts/get') return fakeServerReply(method, params);
      return <String, Object?>{
        'messages': <Object?>[
          <String, Object?>{
            'role': 'assistant',
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': '图：'},
              <String, Object?>{'type': 'image', 'mimeType': 'image/png'},
            ],
          },
        ],
      };
    });
    final McpClient client = newClient();

    final List<McpPromptMessage> messages = await client.getPrompt('review');

    expect(messages.single.text, '图：\n[image/png]');
  });

  test('服务端不支持 prompts/*：返回空表且不断连', () async {
    transport.onSend = (McpMessage message) async {
      final Object? id = message.id;
      final String? method = message.method;
      if (id == null || method == null) return;
      if (method.startsWith('prompts/')) {
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

    expect(await client.listPrompts(), isEmpty);
    expect(await client.getPrompt('review'), isEmpty);
    expect(client.ready, isTrue);
  });
}
