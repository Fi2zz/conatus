import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

const String _preference = '记住：以后都用中文回答';

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.script);

  final List<LlmResult> script;
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(List<LlmMessage>.of(messages));
    final int index =
        calls.length - 1 < script.length ? calls.length - 1 : script.length - 1;
    return script[index];
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

/// 一段真实格式的多轮对话：每轮「提问 → 工具调用 → 大结果 → 收口」。
Session _dialog({int rounds = 24}) {
  final Session session = Session(id: 's1');
  for (int round = 0; round < rounds; round++) {
    session.append(kUserMessageEvent, data: <String, Object?>{
      'text': round == 2 ? _preference : '第$round个问题',
    });
    session.append(kAssistantMessageEvent, data: <String, Object?>{
      'text': '',
      'toolCalls': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'c$round',
          'name': 'read_file',
          'arguments': '{"path":"a.txt"}',
        },
      ],
    });
    session.append(kToolResultEvent, data: <String, Object?>{
      'callId': 'c$round',
      'name': 'read_file',
      'content': '文件$round首行${'x' * 5000}\n文件$round结尾',
      'isError': false,
    });
    session.append(kAssistantMessageEvent,
        data: <String, Object?>{'text': '第$round轮读完'});
  }
  return session;
}

String _text(SessionEvent event) =>
    '${(event.data as Map<String, Object?>)['text'] ?? ''}';

void main() {
  group('LayeredCompactor — 分层压缩', () {
    test('事件数不超过保留数时不压缩', () async {
      final LayeredCompactor compactor = LayeredCompactor(keepRecent: 8);

      final CompactionResult? result = await compactor.compactIfNeeded(
          _dialog(rounds: 2), (_, __) async => const CompactionSummary('x'));

      expect(result, isNull);
      expect(compactor.summaryOf('s1'), isNull);
    });

    test('偏好原文保留、工具结果压成摘要 + 指针', () async {
      final Session session = _dialog();
      final LayeredCompactor compactor = LayeredCompactor(keepRecent: 8);
      final List<SessionEvent> summarized = <SessionEvent>[];

      final CompactionResult result = (await compactor.compactIfNeeded(
        session,
        (List<SessionEvent> events, String previous) async {
          summarized.addAll(events);
          return const CompactionSummary('用户逐一读取了 24 个文件');
        },
      ))!;

      expect(result.compacted, 88);
      expect(result.kept, 8);
      expect(compactor.summaryOf('s1'), result.summary);
      // ① 分层结构：三段小节
      expect(result.summary, contains('[历史摘要]'));
      expect(result.summary, contains('用户逐一读取了 24 个文件'));
      // ② 用户偏好原文保留
      expect(result.summary, contains('[用户偏好]'));
      expect(result.summary, contains(_preference));
      // ③ 工具结果只有「摘要 + 指针」，正文没整体进入摘要
      expect(result.summary, contains('[工具结果]'));
      expect(result.summary, contains('工具 read_file：文件0首行'));
      expect(result.summary, contains('字符'));
      expect(result.summary, contains('会话日志'));
      expect(result.summary.contains('x' * 200), isFalse);
      // ④ 早期对话才交给汇总器：工具结果与偏好都不进汇总器
      expect(summarized, isNotEmpty);
      expect(
          summarized.every((SessionEvent e) =>
              e.type == kUserMessageEvent || e.type == kAssistantMessageEvent),
          isTrue);
      expect(summarized.map(_text), isNot(contains(_preference)));
      // ⑤ 摘要体量显著小于原文
      final int before = estimateMessagesTokens(
          deriveAgentMessages(session.events.sublist(0, result.compacted)));
      expect(estimateTokens(result.summary) * 2, lessThan(before));
    });

    test('超过分类器窗口的近期对话按 keep 保留原文', () async {
      final Session session = Session(id: 's1');
      for (int i = 0; i < 8; i++) {
        session
            .append(kUserMessageEvent, data: <String, Object?>{'text': '第$i条'});
      }
      final LayeredCompactor compactor = LayeredCompactor(
        keepRecent: 2,
        classifier: RuleBasedContentClassifier(recentWindow: 5),
      );

      final CompactionResult result = (await compactor.compactIfNeeded(
          session, (_, __) async => const CompactionSummary('摘要')))!;

      expect(result.summary, contains('[保留原文]'));
      expect(result.summary, contains('第3条'));
      expect(result.summary, contains('第5条'));
      expect(result.summary, isNot(contains('第0条')));
    });

    test('第二次压缩把上一版摘要交给汇总器', () async {
      final Session session = _dialog();
      final LayeredCompactor compactor = LayeredCompactor(keepRecent: 8);
      final List<String> previous = <String>[];

      await compactor.compactIfNeeded(session,
          (List<SessionEvent> events, String prev) async {
        previous.add(prev);
        return const CompactionSummary('v1');
      });
      await compactor.compactIfNeeded(session,
          (List<SessionEvent> events, String prev) async {
        previous.add(prev);
        return const CompactionSummary('v2');
      });

      expect(previous.first, '');
      expect(previous.last, contains('v1'));
      expect(compactor.summaryOf('s1'), contains('v2'));
    });

    test('汇总器抛错时摘要记忆不更新', () async {
      final Session session = _dialog();
      final LayeredCompactor compactor = LayeredCompactor(keepRecent: 8);
      await compactor.compactIfNeeded(
          session, (_, __) async => const CompactionSummary('旧摘要'));
      final String? before = compactor.summaryOf('s1');

      await expectLater(
        compactor.compactIfNeeded(session, (_, __) async {
          throw StateError('boom');
        }),
        throwsStateError,
      );

      expect(before, isNotNull);
      expect(compactor.summaryOf('s1'), before);
    });

    test('forget 丢弃摘要', () async {
      final LayeredCompactor compactor = LayeredCompactor(keepRecent: 1);
      final Session session = Session(id: 's1')
        ..append(kUserMessageEvent, data: <String, Object?>{'text': 'a'})
        ..append(kAssistantMessageEvent, data: <String, Object?>{'text': 'b'});
      await compactor.compactIfNeeded(
          session, (_, __) async => const CompactionSummary('摘要'));

      compactor.forget('s1');

      expect(compactor.summaryOf('s1'), isNull);
    });
  });

  group('LayeredCompactor — 遥测与装配', () {
    test('发 context.compacted，含压缩前后 token 估算', () async {
      final InMemoryTelemetry telemetry = InMemoryTelemetry();

      final CompactionResult result = (await LayeredCompactor(
        keepRecent: 8,
        telemetry: telemetry,
      ).compactIfNeeded(
          _dialog(), (_, __) async => const CompactionSummary('摘要')))!;

      final TelemetryEvent event = telemetry.recent.single;
      expect(event.name, 'context.compacted');
      expect(event.data['compacted'], result.compacted);
      expect(event.data['kept'], 8);
      expect(event.data['toolResults'], 22);
      expect(event.data['preferences'], 1);
      expect(event.data['tokensBefore'] as int,
          greaterThan(event.data['tokensAfter'] as int));
      await telemetry.close();
    });

    test('没有 telemetry 时不发事件也不报错', () async {
      final CompactionResult? result = await LayeredCompactor(keepRecent: 8)
          .compactIfNeeded(
              _dialog(), (_, __) async => const CompactionSummary('摘要'));

      expect(result, isNotNull);
    });

    test('provideLayeredCompaction 注册到 compaction 键', () {
      final Context ctx = Context.root();

      final LayeredCompactor compactor =
          provideLayeredCompaction(ctx, keepRecent: 5);

      expect(
          identical(ctx.require<Compactor>('compaction'), compactor), isTrue);
      expect(compactor.keepRecent, 5);
      expect(compactor.classifier, isA<RuleBasedContentClassifier>());
      ctx.dispose();
    });

    test('从上下文取分类器与遥测', () async {
      final Context ctx = Context.root();
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      provideTelemetry(ctx, telemetry: telemetry);
      final ContentClassifier classifier = provideContentClassifier(ctx);
      final LayeredCompactor compactor = provideLayeredCompaction(ctx);

      expect(identical(compactor.classifier, classifier), isTrue);
      await compactor.compactIfNeeded(
          _dialog(), (_, __) async => const CompactionSummary('摘要'));
      expect(telemetry.recent.single.name, 'context.compacted');
      ctx.dispose();
    });

    test('可作为 Compactor 直接替换进 AgentLoop', () async {
      final Session session = Session(id: 's1');
      for (int i = 0; i < 4; i++) {
        session
            .append(kUserMessageEvent, data: <String, Object?>{'text': '第$i条'});
      }
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        const LlmResult(content: '这是摘要', provider: 'scripted', model: 'm'),
        const LlmResult(content: '最终回复', provider: 'scripted', model: 'm'),
      ]);
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: ToolRegistry(),
        session: session,
        compactor: LayeredCompactor(keepRecent: 1),
      );

      final AgentTurn turn = await loop.run('新问题');

      // 压缩在日志末尾留下 start / summary / end 三个记录事件。
      expect(session.events.map((SessionEvent e) => e.type), <String>[
        kUserMessageEvent,
        kUserMessageEvent,
        kUserMessageEvent,
        kUserMessageEvent,
        kUserMessageEvent,
        kCompactionStartEvent,
        kCompactionSummaryEvent,
        kCompactionEndEvent,
        kAssistantMessageEvent,
      ]);
      expect(checkCompactionInvariant(session.events), isEmpty);
      expect(provider.calls, hasLength(2));
      expect(provider.calls.last.first.content, contains('[历史摘要]'));
      expect(provider.calls.last.first.content, contains('这是摘要'));
      expect(turn.reply, '最终回复');
    });
  });
}
