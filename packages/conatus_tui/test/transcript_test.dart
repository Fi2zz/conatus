/// 会话事件 → 屏上消息的投射。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

void main() {
  test('回放会话事件：用户 / 工具调用 / 工具结果 / 助手', () {
    final Session session = Session(id: 's');
    session.append(kUserMessageEvent, data: <String, Object?>{'text': '几点？'});
    session.append(kAssistantMessageEvent, data: <String, Object?>{
      'text': '',
      'toolCalls': <Map<String, Object?>>[
        <String, Object?>{
          'id': '1',
          'name': 'get_time',
          'arguments': '{}',
        },
      ],
    });
    session.append(kToolResultEvent, data: <String, Object?>{
      'callId': '1',
      'name': 'get_time',
      'content': '12:00',
      'isError': false,
    });
    session.append(kAssistantMessageEvent,
        data: <String, Object?>{'text': '现在是 12:00。'});

    final Transcript transcript = Transcript()..rebuildFrom(session);

    expect(
      transcript.messages.map((TuiMessage m) => m.role).toList(),
      <TuiRole>[TuiRole.user, TuiRole.stage, TuiRole.tool, TuiRole.assistant],
    );
    expect(transcript.messages[1].text, contains('get_time'));
    expect(transcript.messages[2].text, contains('✓'));
    expect(transcript.messages[3].text, '现在是 12:00。');
  });

  test('失败的工具结果标记为 ✗ 并带内容预览', () {
    final Session session = Session(id: 's');
    session.append(kToolResultEvent, data: <String, Object?>{
      'callId': '1',
      'name': 'read_file',
      'content': '错误：文件不存在',
      'isError': true,
    });

    final Transcript transcript = Transcript()..rebuildFrom(session);

    expect(transcript.messages.single.role, TuiRole.tool);
    expect(transcript.messages.single.text, contains('✗'));
    expect(transcript.messages.single.text, contains('文件不存在'));
  });

  test('空助手事件（工具调用轮）不产生空气泡', () {
    final Session session = Session(id: 's');
    session.append(kAssistantMessageEvent,
        data: <String, Object?>{'text': '', 'toolCalls': <Object>[]});

    final Transcript transcript = Transcript()..rebuildFrom(session);

    expect(transcript.messages, isEmpty);
  });
}
