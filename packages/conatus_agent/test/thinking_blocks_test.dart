/// Anthropic thinking 块随会话事件往返，供下一轮 tool loop 回传。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

void main() {
  test('deriveAgentMessages 还原 thinkingBlocks', () {
    final List<LlmMessage> messages = deriveAgentMessages(<SessionEvent>[
      SessionEvent.create(
        sessionId: 's',
        type: kAssistantMessageEvent,
        seq: 1,
        data: <String, Object?>{
          'text': '答案',
          'thinkingBlocks': <Map<String, Object?>>[
            <String, Object?>{
              'type': 'thinking',
              'thinking': '先想',
              'signature': 'sig123',
            },
          ],
        },
      ),
    ]);

    expect(messages.single.thinkingBlocks.single['signature'], 'sig123');
  });
}
