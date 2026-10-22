import 'dart:convert';

import 'package:conatus_context/conatus_context.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

void main() {
  final List<ContentCompressor> compressors = <ContentCompressor>[
    const JsonArrayCompressor(),
  ];

  test('只压缩指定 role 的消息并保留全部字段', () async {
    final List<LlmMessage> out = await compressMessages(
      <LlmMessage>[
        LlmMessage('user', List<String>.filled(1000, 'x').join()),
        LlmMessage(
          'tool',
          jsonEncode(
              List<Map<String, Object?>>.filled(50, <String, Object?>{'a': 'b'})),
          toolCallId: 'c1',
        ),
      ],
      config: const ContextCompressionConfig(minChars: 10),
      compressors: compressors,
    );
    expect(out[0].content, List<String>.filled(1000, 'x').join());
    expect(out[1].content, contains('<<ctx:'));
    expect(out[1].toolCallId, 'c1');
  });

  test('重复调用结果不变（幂等）', () async {
    final List<LlmMessage> input = <LlmMessage>[
      LlmMessage(
        'tool',
        jsonEncode(
            List<Map<String, Object?>>.filled(50, <String, Object?>{'a': 'b'})),
        toolCallId: 'c1',
      ),
    ];
    final List<LlmMessage> once = await compressMessages(input,
        config: const ContextCompressionConfig(minChars: 10),
        compressors: compressors);
    final List<LlmMessage> twice = await compressMessages(once,
        config: const ContextCompressionConfig(minChars: 10),
        compressors: compressors);
    expect(twice.single.content, once.single.content);
  });

  test('空列表原样返回', () async {
    expect(await compressMessages(const <LlmMessage>[]), isEmpty);
  });
}
