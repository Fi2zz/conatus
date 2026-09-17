/// TraceBuilder 测试的公共构造：固定时间基准、事件构建器与内存日志填充。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_observability/conatus_observability.dart';

/// 测试用固定基准时间。
DateTime t(int second) => DateTime(2026, 9, 17).add(Duration(seconds: second));

/// 构造一条事件（seq 由日志覆盖）。
SessionEvent eventAt(String id, String type, int second, {Object? data}) =>
    SessionEvent.create(
      sessionId: 's1',
      type: type,
      seq: 0,
      id: id,
      time: t(second),
      data: data,
    );

SessionEvent userMessage(String id, int second) =>
    eventAt(id, kUserMessageEvent, second, data: <String, Object?>{'text': 'hi'});

SessionEvent assistantMessage(String id, int second) => eventAt(
    id, kAssistantMessageEvent, second,
    data: <String, Object?>{'text': 'ok'});

SessionEvent llmRequest(String id, int second) => eventAt(
    id, kLlmRequestEvent, second,
    data: <String, Object?>{'provider': 'doubao'});

SessionEvent llmResponse(String id, int second) => eventAt(
    id, kLlmResponseEvent, second,
    data: <String, Object?>{
      'provider': 'doubao',
      'model': 'seed-1',
      'usage': <String, Object?>{'prompt_tokens': 10},
    });

SessionEvent toolCall(String id, int second, {required String callId}) =>
    eventAt(id, kToolCallEvent, second,
        data: <String, Object?>{'name': 'shell', 'callId': callId});

SessionEvent toolResult(String id, int second,
        {required String callId, bool isError = false}) =>
    eventAt(id, kToolResultEvent, second,
        data: <String, Object?>{
          'name': 'shell',
          'callId': callId,
          'isError': isError,
        });

SessionEvent teamSpawned(String id, int second) => eventAt(
    id, kTeamSpawnedEvent, second,
    data: <String, Object?>{'name': 'alice', 'teammateId': 'm1'});

SessionEvent teamRemoved(String id, int second) => eventAt(
    id, kTeamRemovedEvent, second,
    data: <String, Object?>{'teammateId': 'm1', 'completed': true});

/// 用事件序列填充内存日志。
Future<InMemorySessionLog> seedLog(List<SessionEvent> events) async {
  final InMemorySessionLog log = InMemorySessionLog();
  for (final SessionEvent event in events) {
    await log.append(event);
  }
  return log;
}
