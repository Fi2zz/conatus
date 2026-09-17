import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_observability/conatus_observability.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('TraceBuilder', () {
    test('单轮：根 span + llm + tool 子 span，层级与时长从事件时间戳派生', () async {
      final InMemorySessionLog log = await seedLog(<SessionEvent>[
        userMessage('u1', 0),
        llmRequest('r1', 1),
        llmResponse('p1', 3),
        assistantMessage('a1', 3),
        toolCall('t1', 4, callId: 'c1'),
        toolResult('x1', 7, callId: 'c1'),
        assistantMessage('a2', 7),
      ]);

      final List<Span> spans =
          await TraceBuilder(sessionLog: log).buildTrace('s1');

      expect(spans, hasLength(3));
      final Span root = spans[0];
      expect(root.name, kTurnSpanName);
      expect(root.spanId, 'u1');
      expect(root.traceId, 'u1');
      expect(root.parentSpanId, isNull);
      expect(root.startTime, t(0));
      expect(root.duration, const Duration(seconds: 7));
      expect(root.status, SpanStatus.ok);

      final Span llm = spans[1];
      expect(llm.name, kLlmSpanName);
      expect(llm.traceId, root.traceId);
      expect(llm.parentSpanId, root.spanId);
      expect(llm.startTime, t(1));
      expect(llm.duration, const Duration(seconds: 2));
      expect(llm.status, SpanStatus.ok);
      expect(llm.attributes['model'], 'seed-1');

      final Span tool = spans[2];
      expect(tool.name, kToolSpanName);
      expect(tool.traceId, root.traceId);
      expect(tool.parentSpanId, root.spanId);
      expect(tool.startTime, t(4));
      expect(tool.duration, const Duration(seconds: 3));
      expect(tool.status, SpanStatus.ok);
    });

    test('多轮：每个 user/message 一个独立 trace，子 span 归属本轮的根', () async {
      final InMemorySessionLog log = await seedLog(<SessionEvent>[
        userMessage('u1', 0),
        llmRequest('r1', 1),
        llmResponse('p1', 2),
        assistantMessage('a1', 2),
        userMessage('u2', 10),
        llmRequest('r2', 11),
        llmResponse('p2', 12),
        assistantMessage('a2', 12),
      ]);

      final List<Span> spans =
          await TraceBuilder(sessionLog: log).buildTrace('s1');

      expect(spans, hasLength(4));
      final Span root1 = spans[0];
      final Span root2 = spans[2];
      expect(root1.spanId, 'u1');
      expect(root2.spanId, 'u2');
      expect(root1.traceId, isNot(root2.traceId));
      expect(root1.duration, const Duration(seconds: 10));
      expect(root2.duration, const Duration(seconds: 2));
      expect(spans[1].parentSpanId, root1.spanId);
      expect(spans[3].parentSpanId, root2.spanId);
    });

    test('tool/result isError 时 tool.call span 状态为 error', () async {
      final InMemorySessionLog log = await seedLog(<SessionEvent>[
        userMessage('u1', 0),
        toolCall('t1', 1, callId: 'c1'),
        toolResult('x1', 2, callId: 'c1', isError: true),
      ]);

      final List<Span> spans =
          await TraceBuilder(sessionLog: log).buildTrace('s1');

      expect(spans, hasLength(2));
      expect(spans[1].status, SpanStatus.error);
      expect(spans[0].status, SpanStatus.ok);
    });

    test('llm/request 无对应 response：span 保持 unset，时长到日志末尾', () async {
      final InMemorySessionLog log = await seedLog(<SessionEvent>[
        userMessage('u1', 0),
        llmRequest('r1', 1),
      ]);

      final List<Span> spans =
          await TraceBuilder(sessionLog: log).buildTrace('s1');

      expect(spans, hasLength(2));
      expect(spans[1].name, kLlmSpanName);
      expect(spans[1].status, SpanStatus.unset);
      expect(spans[1].duration, Duration.zero);
    });

    test('tool/call 无对应 result：span 保持 unset', () async {
      final InMemorySessionLog log = await seedLog(<SessionEvent>[
        userMessage('u1', 0),
        toolCall('t1', 1, callId: 'c1'),
      ]);

      final List<Span> spans =
          await TraceBuilder(sessionLog: log).buildTrace('s1');

      expect(spans, hasLength(2));
      expect(spans[1].status, SpanStatus.unset);
    });

    test('连续两次 llm 调用：各配对到自己的 response', () async {
      final InMemorySessionLog log = await seedLog(<SessionEvent>[
        userMessage('u1', 0),
        llmRequest('r1', 1),
        llmResponse('p1', 3),
        assistantMessage('a1', 3),
        llmRequest('r2', 4),
        llmResponse('p2', 6),
        assistantMessage('a2', 6),
      ]);

      final List<Span> spans =
          await TraceBuilder(sessionLog: log).buildTrace('s1');

      expect(spans, hasLength(3));
      expect(spans[1].spanId, 'r1');
      expect(spans[1].duration, const Duration(seconds: 2));
      expect(spans[2].spanId, 'r2');
      expect(spans[2].duration, const Duration(seconds: 2));
    });

    test('team/spawned×team/removed：subagent.spawn 配对闭合', () async {
      final InMemorySessionLog log = await seedLog(<SessionEvent>[
        userMessage('u1', 0),
        teamSpawned('sp1', 1),
        teamRemoved('rm1', 4),
        assistantMessage('a1', 4),
      ]);

      final List<Span> spans =
          await TraceBuilder(sessionLog: log).buildTrace('s1');

      expect(spans, hasLength(2));
      final Span subagent = spans[1];
      expect(subagent.name, kSubagentSpanName);
      expect(subagent.parentSpanId, spans[0].spanId);
      expect(subagent.startTime, t(1));
      expect(subagent.duration, const Duration(seconds: 3));
      expect(subagent.status, SpanStatus.ok);
    });

    test('空会话返回空 span 列表', () async {
      final InMemorySessionLog log = await seedLog(const <SessionEvent>[]);

      final List<Span> spans =
          await TraceBuilder(sessionLog: log).buildTrace('empty');

      expect(spans, isEmpty);
    });
  });
}
