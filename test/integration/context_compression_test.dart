import 'dart:convert';

import 'package:conatus/conatus.dart';
import 'package:test/test.dart';

import 'helpers/scripted_llm.dart';
import 'helpers/test_harness.dart';

class _BigJsonTool extends Tool {
  @override
  String get name => 'big_json';

  @override
  String get description => '返回大 JSON';

  @override
  Future<ToolResult> call(ToolContext context) async => ToolResult.success(
        jsonEncode(<Map<String, Object?>>[
          for (int i = 0; i < 300; i++)
            <String, Object?>{'id': i, 'status': i == 7 ? 500 : 200},
        ]),
      );
}

void main() {
  test('大 JSON 工具结果在进入模型前被压缩，且不变式成立', () async {
    final TestHarness harness = await TestHarness.create(
      llmScript: <LlmResult>[
        callTool('c1', 'big_json'),
        text('done'),
      ],
      configure: (Context app, Session session) {
        app.effect(() => app.tools.register(_BigJsonTool()));
        provideSessionLogRecorder(app);
        provideContextCompression(
          app,
          config: const ContextCompressionConfig(minChars: 100),
        );
      },
    );

    await harness.run('跑一下');

    final String toolMessage = harness.llm.requests.last
        .firstWhere((LlmMessage message) => message.role == 'tool')
        .content;
    expect(toolMessage, contains('<<ctx:'));
    expect(toolMessage.length, lessThan(5000));

    final SessionLog log = harness.app.require<SessionLog>('sessionLog');
    await harness.settle();
    final List<SessionEvent> events = <SessionEvent>[];
    await log.replay(harness.session.id, events.add);
    expect(checkModelVisibleInvariant(events), isEmpty);

    final String id = parseCcrMarker(toolMessage)!.id;
    final ToolResult retrieved = await harness.app.tools.call(
      ToolCall(
        name: 'context_retrieve',
        arguments: <String, Object?>{'id': id},
      ),
    );
    expect(retrieved.content, contains('"id":0'));
    expect(jsonDecode(retrieved.content), isA<List<dynamic>>());
  });
}
