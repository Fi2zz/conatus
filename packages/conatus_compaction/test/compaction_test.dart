import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

Session _session(int events) {
  final Session session = Session(id: 's1');
  for (int i = 0; i < events; i++) {
    session.append('e$i');
  }
  return session;
}

/// 造一段「用户 → 助手发起工具调用 → 工具结果」的日志。
Session _toolSession() {
  final Session session = Session(id: 's1');
  session.append(kUserMessageEvent, data: <String, Object?>{'text': '查一下'});
  session.append(kAssistantMessageEvent, data: <String, Object?>{
    'text': '',
    'toolCalls': <Map<String, Object?>>[
      <String, Object?>{'id': 'c1', 'name': 'search', 'arguments': '{}'},
    ],
  });
  session.append(kToolResultEvent,
      data: <String, Object?>{'callId': 'c1', 'content': '结果'});
  return session;
}

void main() {
  group('Compactor', () {
    test('事件数不超过保留数时不压缩', () async {
      final Compactor compactor = Compactor(keepRecent: 3);
      final Session session = _session(3);

      final CompactionResult? result =
          await compactor.compactIfNeeded(session, (_, __) async {
        return const CompactionSummary('x');
      });

      expect(result, isNull);
      expect(compactor.summaryOf('s1'), isNull);
      expect(session.length, 3);
    });

    test('折叠较早事件、保留最近若干条', () async {
      final Compactor compactor = Compactor(keepRecent: 2);
      final Session session = _session(5);
      List<SessionEvent>? folded;

      final CompactionResult result = (await compactor.compactIfNeeded(
        session,
        (List<SessionEvent> events, String previous) async {
          folded = events;
          return const CompactionSummary('摘要');
        },
      ))!;

      expect(result.compacted, 3);
      expect(result.kept, 2);
      expect(result.summary, '摘要');
      expect(result.shadowedSeqs, <int>[0, 1, 2]);
      expect(
          folded!.map((SessionEvent e) => e.type), <String>['e0', 'e1', 'e2']);
      expect(compactor.summaryOf('s1'), '摘要');
    });

    test('在日志末尾留下 start / summary / end 三个同身份事件', () async {
      final Compactor compactor = Compactor(keepRecent: 2);
      final Session session = _session(5);

      final CompactionResult result = (await compactor.compactIfNeeded(
        session,
        (_, __) async => const CompactionSummary('摘要',
            provider: 'fake', model: 'fake-model'),
      ))!;

      final List<SessionEvent> events = session.events;
      expect(events.sublist(5).map((SessionEvent e) => e.type), <String>[
        kCompactionStartEvent,
        kCompactionSummaryEvent,
        kCompactionEndEvent
      ]);
      expect(result.startSeq, 5);
      expect(result.summarySeq, 6);
      expect(result.endSeq, 7);
      final Map<Object?, Object?> payload =
          events[6].data! as Map<Object?, Object?>;
      expect(payload['compactionId'], result.compactionId);
      expect(payload['shadowedSeqs'], <int>[0, 1, 2]);
      expect(payload['kept'], 2);
      expect(payload['provider'], 'fake');
      expect(payload['model'], 'fake-model');
      expect(checkCompactionInvariant(events), isEmpty);
    });

    test('第二次压缩把上一版摘要交给汇总器', () async {
      final Compactor compactor = Compactor(keepRecent: 1);
      final Session session = _session(3);
      final List<String> previous = <String>[];

      Future<CompactionSummary> summarize(_, String prev) async {
        previous.add(prev);
        return CompactionSummary('v${previous.length}');
      }

      await compactor.compactIfNeeded(session, summarize);
      await compactor.compactIfNeeded(session, summarize);

      expect(previous, <String>['', 'v1']);
      expect(compactor.summaryOf('s1'), 'v2');
    });

    test('汇总器抛错时摘要记忆不更新、end 记录错误', () async {
      final Compactor compactor = Compactor(keepRecent: 1);
      final Session session = _session(3);

      await expectLater(
        compactor.compactIfNeeded(session, (_, __) async {
          throw StateError('boom');
        }),
        throwsStateError,
      );

      expect(compactor.summaryOf('s1'), isNull);
      final SessionEvent end = session.events.last;
      expect(end.type, kCompactionEndEvent);
      expect((end.data! as Map<Object?, Object?>)['error'], contains('boom'));
      expect(checkCompactionInvariant(session.events), isEmpty);
    });

    test('forget 丢弃摘要', () async {
      final Compactor compactor = Compactor(keepRecent: 1);
      final Session session = _session(2);
      await compactor.compactIfNeeded(
          session, (_, __) async => const CompactionSummary('摘要'));

      compactor.forget('s1');
      expect(compactor.summaryOf('s1'), isNull);
    });

    test('keepRecent 为负时构造抛错', () {
      expect(() => Compactor(keepRecent: -1), throwsArgumentError);
    });

    test('切点不会劈开工具调用与其结果', () async {
      final Compactor compactor = Compactor(keepRecent: 1);
      final Session session = _toolSession();

      final CompactionResult result = (await compactor.compactIfNeeded(
        session,
        (_, __) async => const CompactionSummary('摘要'),
      ))!;

      // 预算切点是 2（会只剩 tool/result），吸附到 1：折叠用户消息，工具对留在原文。
      expect(result.compacted, 1);
      expect(result.kept, 2);
      expect(result.shadowedSeqs, <int>[0]);
    });

    test('整段都不可安全切分时不压缩', () async {
      final Compactor compactor = Compactor(keepRecent: 0);
      final Session session = Session(id: 's1')
        ..append(kAssistantMessageEvent, data: <String, Object?>{
          'text': '',
          'toolCalls': <Map<String, Object?>>[
            <String, Object?>{'id': 'c1', 'name': 'search', 'arguments': '{}'},
          ],
        });

      final CompactionResult? result = await compactor.compactIfNeeded(
          session, (_, __) async => const CompactionSummary('摘要'));

      expect(result, isNull);
      expect(session.length, 1);
    });

    test('可传入覆盖本次调用的预算', () async {
      final Compactor compactor = Compactor(keepRecent: 10);
      final Session session = _session(5);

      final CompactionResult result = (await compactor.compactIfNeeded(
        session,
        (_, __) async => const CompactionSummary('摘要'),
        keepRecent: 1,
      ))!;

      expect(result.compacted, 4);
      expect(result.kept, 1);
      expect(compactor.keepRecent, 10);
    });
  });

  test('provideCompaction 作为 compaction 服务提供', () {
    final ctx = Context.root();
    final CompactionEngine engine = provideCompaction(ctx);
    expect(
        identical(ctx.require<CompactionEngine>('compaction'), engine), isTrue);
    ctx.dispose();
  });
}
