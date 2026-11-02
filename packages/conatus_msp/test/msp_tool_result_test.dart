import 'package:conatus_msp/src/msp_tool_result.dart';
import 'package:test/test.dart';

void main() {
  test('工具处理器可直接返回完整 ToolResult', () {
    const MspToolResult original =
        MspToolResult(structured: <String, Object?>{'ok': true});

    expect(MspToolResult.fromValue(original), same(original));
  });

  test('非空 content block 列表保持块结构且不写入 structured', () {
    final List<Map<String, Object?>> blocks = <Map<String, Object?>>[
      <String, Object?>{'type': 'text', 'text': '你好'},
      <String, Object?>{'type': 'future_block', 'value': 1},
    ];

    final MspToolResult result = MspToolResult.fromValue(blocks);
    expect(result.content, blocks);
    expect(result.structured, isNull);
    expect(result.toPayload()['structuredContent'], isNull);
  });

  test('空列表仍走 structured 分支', () {
    final MspToolResult result = MspToolResult.fromValue(<Object?>[]);

    expect(result.structured, <Object?>[]);
    expect(result.content.single['text'], '[]');
  });
}
