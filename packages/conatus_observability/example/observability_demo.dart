/// conatus_observability 的可运行示例：从 Session Log 派生并打印 trace。
///
/// 完全离线，不需要 API Key：用 [InMemorySessionLog] 模拟一次会话的事件序列
/// （与真实 `SessionLogRecorder` 落盘的形态一致），再用 [TraceBuilder]
/// 派生 span 层级。
///
/// 运行：`dart run example/observability_demo.dart`
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_observability/conatus_observability.dart';

Future<void> main() async {
  final InMemorySessionLog log = InMemorySessionLog();
  final DateTime base = DateTime(2026, 9, 17, 12);

  await _append(log, base, kUserMessageEvent, 'u1', 0,
      <String, Object?>{'text': '查一下明天的机票'});
  await _append(log, base, kLlmRequestEvent, 'r1', 1,
      <String, Object?>{'provider': 'doubao'});
  await _append(log, base, kLlmResponseEvent, 'p1', 4, <String, Object?>{
    'provider': 'doubao',
    'model': 'seed-1',
    'usage': <String, Object?>{'prompt_tokens': 120, 'completion_tokens': 40},
  });
  await _append(log, base, kAssistantMessageEvent, 'a1', 4,
      <String, Object?>{'text': '我来查询航班…'});
  await _append(log, base, kToolCallEvent, 't1', 5, <String, Object?>{
    'name': 'search_flights',
    'callId': 'call-1',
  });
  await _append(log, base, kToolResultEvent, 'x1', 9, <String, Object?>{
    'name': 'search_flights',
    'callId': 'call-1',
    'isError': false,
  });
  await _append(log, base, kAssistantMessageEvent, 'a2', 9,
      <String, Object?>{'text': '找到 3 个航班…'});

  final List<Span> spans =
      await TraceBuilder(sessionLog: log).buildTrace('flight-session');

  print('会话 flight-session 派生 ${spans.length} 个 span：\n');
  for (final Span span in spans) {
    final String role = span.parentSpanId == null ? 'root' : 'child';
    final int startSec = span.startTime.difference(base).inSeconds;
    print('  - ${span.name} [$role] '
        't+${startSec}s 耗时 ${span.duration.inMilliseconds}ms '
        '状态 ${span.status.name}');
  }
}

Future<void> _append(
  SessionLog log,
  DateTime base,
  String type,
  String id,
  int second,
  Map<String, Object?> data,
) =>
    log.append(SessionEvent.create(
      sessionId: 'flight-session',
      type: type,
      seq: 0,
      id: id,
      data: data,
      time: base.add(Duration(seconds: second)),
    ));
