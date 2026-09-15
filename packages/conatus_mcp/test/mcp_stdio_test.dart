@Tags(<String>['integration'])
library;

import 'dart:io';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

/// 用真实子进程（`dart run test/fixtures/echo_mcp_server.dart`）跑通 stdio 链路。
void main() {
  test('stdio 端到端：握手 / 发现工具 / 调用回显', () async {
    final StdioTransport transport = StdioTransport(
      command: Platform.resolvedExecutable,
      args: <String>['run', 'test/fixtures/echo_mcp_server.dart'],
    );
    final McpClient client = McpClient(
      transport: transport,
      serverName: 'echo',
    );
    final List<String> diagnostics = <String>[];
    client.diagnostics.listen(diagnostics.add);

    try {
      final McpServerInfo info = await client.initialize();
      expect(info.name, 'echo');
      expect(info.version, '0.0.1');
      expect(info.protocolVersion, '2025-06-18');
      expect(client.ready, isTrue);

      final List<McpTool> tools = await client.listTools();
      expect(tools.single.name, 'echo');
      expect(tools.single.description, '原样回显 arguments');
      expect(
        tools.single.inputSchema['required'],
        <String>['text'],
      );

      final McpToolResult result = await client.callTool(
        'echo',
        <String, Object?>{'text': '你好', 'n': 2},
      );
      expect(result.failed, isFalse);
      expect(
        describeMcpContent(result.content),
        '{"text":"你好","n":2}',
      );
      expect(
        result.structuredContent,
        <String, Object?>{'text': '你好', 'n': 2},
      );
    } on McpException catch (error) {
      if (error.code == 'timeout' || error.code == 'server-exited') {
        markTestSkipped('本机无法用 dart run 起本地 MCP server：${error.code}');
        return;
      }
      rethrow;
    } finally {
      await client.close();
    }

    expect(transport.connected, isFalse);
  });
}
