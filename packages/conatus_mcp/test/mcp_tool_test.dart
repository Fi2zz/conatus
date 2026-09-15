import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';
import 'fake_transport.dart';

McpTool _tool({
  String name = 'read_file',
  String? description,
  String? title,
  Map<String, Object?> schema = const <String, Object?>{},
  Map<String, Object?> annotations = const <String, Object?>{},
  String? riskLevel,
}) =>
    McpTool(
      name: name,
      description: description,
      title: title,
      inputSchema: schema,
      annotations: annotations,
      riskLevel: riskLevel,
    );

McpToolAdapter _adapter(McpTool tool, {McpClient? client}) => McpToolAdapter(
      client: client ?? McpClient(transport: FakeTransport(), serverName: 'fs'),
      tool: tool,
    );

void main() {
  group('McpToolAdapter', () {
    test('命名、分组与简介回退', () {
      final McpToolAdapter adapter = _adapter(_tool(description: '读文件'));

      expect(adapter.name, 'fs__read_file');
      expect(mcpToolName('fs', 'read_file'), 'fs__read_file');
      expect(adapter.group, 'mcp:fs');
      expect(adapter.description, '读文件');
      expect(adapter.params, isEmpty);
    });

    test('简介回退顺序：description → title → name', () {
      expect(_adapter(_tool(title: '读取')).description, '读取');
      expect(_adapter(_tool()).description, 'read_file');
    });

    test('toSchema 透传服务端 inputSchema', () {
      final Map<String, Object?> schema = <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'path': <String, Object?>{'type': 'string'},
        },
        'required': <String>['path'],
      };
      final McpToolAdapter adapter = _adapter(_tool(schema: schema));

      expect(adapter.toSchema(), <String, Object?>{
        'name': 'fs__read_file',
        'description': 'read_file',
        'parameters': schema,
      });
    });

    test('inputSchema 为空时回退成空对象 schema', () {
      expect(_adapter(_tool()).toSchema()['parameters'], <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      });
    });

    test('调用成功：内容文本 + 结构化值', () async {
      final FakeTransport transport = FakeTransport();
      autoRespond(transport, (String method, Map<String, Object?>? params) {
        if (method != 'tools/call') return null;
        return <String, Object?>{
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'file body'},
          ],
          'structuredContent': <String, Object?>{'bytes': 9},
        };
      });
      final McpClient client =
          McpClient(transport: transport, serverName: 'fs');
      addTearDown(client.close);
      final McpToolAdapter adapter = _adapter(_tool(), client: client);

      final ToolResult result = await adapter.call(
        const ToolContext(
          ToolCall(
            name: 'fs__read_file',
            arguments: <String, Object?>{'path': '/tmp/a'},
          ),
        ),
      );

      expect(result.isError, isFalse);
      expect(result.content, 'file body');
      expect(result.value, <String, Object?>{'bytes': 9});
      expect(transport.requests.single.params?['name'], 'read_file');
      expect(
        transport.requests.single.params?['arguments'],
        <String, Object?>{'path': '/tmp/a'},
      );
    });

    test('调用失败：isError 映射为 MCP_TOOL_ERROR 失败结果', () async {
      final FakeTransport transport = FakeTransport();
      autoRespond(
        transport,
        (String method, Map<String, Object?>? params) => <String, Object?>{
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': '权限不足'},
          ],
          'isError': true,
        },
      );
      final McpClient client =
          McpClient(transport: transport, serverName: 'fs');
      addTearDown(client.close);

      final ToolResult result = await _adapter(_tool(), client: client)
          .call(const ToolContext(ToolCall(name: 'fs__read_file')));

      expect(result.isError, isTrue);
      expect(result.error?.code, 'MCP_TOOL_ERROR');
      expect(result.error?.message, '权限不足');
    });

    test('客户端异常收敛为 MCP_ERROR 失败结果', () async {
      final McpClient client = McpClient(
        transport: FakeTransport(),
        serverName: 'fs',
        timeout: const Duration(milliseconds: 30),
      );
      addTearDown(client.close);

      final ToolResult result = await _adapter(_tool(), client: client)
          .call(const ToolContext(ToolCall(name: 'fs__read_file')));

      expect(result.isError, isTrue);
      expect(result.error?.code, 'MCP_ERROR');
    });
  });

  group('McpToolAlias', () {
    test('名字换成短别名，其余委托 inner，schema 同步改名', () {
      final McpToolAdapter inner = _adapter(
        _tool(
          description: '读文件',
          annotations: <String, Object?>{'readOnlyHint': true},
          schema: <String, Object?>{'type': 'object'},
        ),
      );
      final McpToolAlias alias = McpToolAlias(inner: inner, alias: 'read_file');

      expect(alias.name, 'read_file');
      expect(alias.description, '读文件');
      expect(alias.group, 'mcp:fs');
      expect(alias.riskLevel, ToolRisk.low);
      expect(alias.toSchema()['name'], 'read_file');
      expect(alias.toSchema()['parameters'], <String, Object?>{
        'type': 'object',
      });
    });

    test('调用透传给 inner', () async {
      final FakeTransport transport = FakeTransport();
      autoRespond(
        transport,
        (String method, Map<String, Object?>? params) => <String, Object?>{
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': '透传'},
          ],
        },
      );
      final McpClient client =
          McpClient(transport: transport, serverName: 'fs');
      addTearDown(client.close);
      final McpToolAlias alias = McpToolAlias(
        inner: _adapter(_tool(), client: client),
        alias: 'read_file',
      );

      final ToolResult result =
          await alias.call(const ToolContext(ToolCall(name: 'read_file')));

      expect(result.content, '透传');
      expect(transport.requests.single.params?['name'], 'read_file');
    });
  });
}
