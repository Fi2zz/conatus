import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('McpTool', () {
    test('解析', () {
      final McpTool tool = McpTool.fromJson(<String, Object?>{
        'name': 'read',
        'title': '读取',
        'description': '读文件',
        'inputSchema': <String, Object?>{'type': 'object'},
        'annotations': <String, Object?>{'readOnlyHint': true},
        'riskLevel': 'readonly',
      });
      expect(tool.name, 'read');
      expect(tool.title, '读取');
      expect(tool.description, '读文件');
      expect(tool.inputSchema['type'], 'object');
      expect(tool.annotations['readOnlyHint'], true);
      expect(tool.riskLevel, 'readonly');

      final McpTool bare = McpTool.fromJson(<String, Object?>{'name': 'x'});
      expect(bare.title, isNull);
      expect(bare.inputSchema, isEmpty);
      expect(bare.annotations, isEmpty);
      expect(bare.riskLevel, isNull);
    });
  });

  group('McpContent', () {
    test('解析与往返', () {
      final McpContent text = McpContent.fromJson(
        <String, Object?>{'type': 'text', 'text': '你好'},
      );
      expect(text.type, 'text');
      expect(text.text, '你好');
      expect(text.toJson(), <String, Object?>{'type': 'text', 'text': '你好'});

      final McpContent image = McpContent.fromJson(<String, Object?>{
        'type': 'image',
        'data': 'AAAA',
        'mimeType': 'image/png',
      });
      expect(image.type, 'image');
      expect(image.mimeType, 'image/png');
      expect(image.toJson()['data'], 'AAAA');
    });

    test('type 缺失时退回 text', () {
      expect(McpContent.fromJson(<String, Object?>{}).type, 'text');
    });
  });

  group('McpToolResult', () {
    test('isError 映射到 failed', () {
      final McpToolResult ok = McpToolResult.fromJson(<String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'a'},
          <String, Object?>{'type': 'text', 'text': 'b'},
          <String, Object?>{'type': 'image', 'mimeType': 'image/png'},
        ],
        'structuredContent': <String, Object?>{'count': 2},
      });
      expect(ok.failed, isFalse);
      expect(ok.content.length, 3);
      expect(ok.structuredContent, <String, Object?>{'count': 2});

      final McpToolResult bad = McpToolResult.fromJson(<String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': '炸了'},
        ],
        'isError': true,
      });
      expect(bad.failed, isTrue);
      expect(bad.structuredContent, isNull);
    });

    test('缺省：空内容、未失败', () {
      final McpToolResult empty = McpToolResult.fromJson(<String, Object?>{});
      expect(empty.content, isEmpty);
      expect(empty.failed, isFalse);
    });
  });

  group('describeMcpContent', () {
    test('文本拼接 + 非文本占位', () {
      expect(
        describeMcpContent(<McpContent>[
          const McpContent(type: 'text', text: '第一行'),
          const McpContent(type: 'text', text: '第二行'),
          const McpContent(type: 'image', mimeType: 'image/png'),
          const McpContent(type: 'resource'),
        ]),
        '第一行\n第二行\n[image/png]\n[resource]',
      );
      expect(describeMcpContent(const <McpContent>[]), '');
    });

    test('空文本块被跳过', () {
      expect(
        describeMcpContent(<McpContent>[
          const McpContent(type: 'text'),
          const McpContent(type: 'text', text: '有内容'),
        ]),
        '有内容',
      );
    });
  });
}
