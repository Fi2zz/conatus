import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

McpTool _tool({
  Map<String, Object?> annotations = const <String, Object?>{},
  String? riskLevel,
}) =>
    McpTool(
      name: 'read_file',
      annotations: annotations,
      riskLevel: riskLevel,
    );

void main() {
  group('mcpToolRisk', () {
    test('什么都没声明 → medium（默认需审批）', () {
      expect(mcpToolRisk(_tool()), ToolRisk.medium);
      expect(
        mcpToolRisk(
          _tool(annotations: <String, Object?>{'idempotentHint': true}),
        ),
        ToolRisk.medium,
      );
    });

    test('readOnlyHint → low，destructiveHint → high', () {
      expect(
        mcpToolRisk(
          _tool(annotations: <String, Object?>{'readOnlyHint': true}),
        ),
        ToolRisk.low,
      );
      expect(
        mcpToolRisk(
          _tool(annotations: <String, Object?>{'destructiveHint': true}),
        ),
        ToolRisk.high,
      );
      expect(
        mcpToolRisk(_tool(annotations: <String, Object?>{
          'readOnlyHint': true,
          'destructiveHint': true,
        })),
        ToolRisk.high,
      );
    });

    test('非标准 riskLevel 优先，大小写不敏感', () {
      expect(mcpToolRisk(_tool(riskLevel: 'READONLY')), ToolRisk.low);
      expect(mcpToolRisk(_tool(riskLevel: 'read')), ToolRisk.low);
      expect(mcpToolRisk(_tool(riskLevel: 'write')), ToolRisk.medium);
      expect(mcpToolRisk(_tool(riskLevel: 'Mutating')), ToolRisk.medium);
      expect(mcpToolRisk(_tool(riskLevel: 'destructive')), ToolRisk.high);
      expect(mcpToolRisk(_tool(riskLevel: 'admin')), ToolRisk.high);
      expect(
        mcpToolRisk(_tool(
          riskLevel: 'readonly',
          annotations: <String, Object?>{'destructiveHint': true},
        )),
        ToolRisk.low,
      );
      expect(mcpToolRisk(_tool(riskLevel: '未知标签')), ToolRisk.medium);
    });
  });

  group('toolResultFromMcp', () {
    test('失败：文本既做内容也做错误消息', () {
      final ToolResult result = toolResultFromMcp(
        const McpToolResult(
          content: <McpContent>[McpContent(type: 'text', text: '炸了')],
          failed: true,
        ),
      );

      expect(result.isError, isTrue);
      expect(result.content, '炸了');
      expect(result.error?.code, 'MCP_TOOL_ERROR');
      expect(result.value, isNull);
    });

    test('成功：结构化结果进 value，非文本给占位', () {
      final ToolResult result = toolResultFromMcp(
        const McpToolResult(
          content: <McpContent>[
            McpContent(type: 'text', text: '看图'),
            McpContent(type: 'image', mimeType: 'image/png'),
          ],
          structuredContent: <String, Object?>{'width': 3},
        ),
      );

      expect(result.isError, isFalse);
      expect(result.content, '看图\n[image/png]');
      expect(result.value, <String, Object?>{'width': 3});
    });
  });
}
