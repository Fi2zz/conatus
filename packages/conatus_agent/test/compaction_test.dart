import 'package:conatus_agent/conatus_agent.dart';
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

void main() {
  group('Compactor', () {
    test('事件数不超过保留数时不压缩', () async {
      final Compactor compactor = Compactor(keepRecent: 3);
      final Session session = _session(3);

      final CompactionResult? result =
          await compactor.compact(session, (_, __) async => 'x');

      expect(result, isNull);
      expect(compactor.summaryOf('s1'), isNull);
    });

    test('折叠较早事件、保留最近若干条', () async {
      final Compactor compactor = Compactor(keepRecent: 2);
      final Session session = _session(5);
      List<SessionEvent>? folded;

      final CompactionResult result = (await compactor.compact(
        session,
        (List<SessionEvent> events, String previous) async {
          folded = events;
          return '摘要';
        },
      ))!;

      expect(result.compacted, 3);
      expect(result.kept, 2);
      expect(result.summary, '摘要');
      expect(
          folded!.map((SessionEvent e) => e.type), <String>['e0', 'e1', 'e2']);
      expect(compactor.summaryOf('s1'), '摘要');
    });

    test('第二次压缩把上一版摘要交给汇总器', () async {
      final Compactor compactor = Compactor(keepRecent: 1);
      final Session session = _session(3);
      final List<String> previous = <String>[];

      await compactor.compact(session, (_, String prev) async {
        previous.add(prev);
        return 'v${previous.length}';
      });
      await compactor.compact(session, (_, String prev) async {
        previous.add(prev);
        return 'v${previous.length}';
      });

      expect(previous, <String>['', 'v1']);
      expect(compactor.summaryOf('s1'), 'v2');
    });

    test('汇总器抛错时摘要记忆不更新', () async {
      final Compactor compactor = Compactor(keepRecent: 1);
      final Session session = _session(3);

      await expectLater(
        compactor.compact(session, (_, __) async => throw StateError('boom')),
        throwsStateError,
      );
      expect(compactor.summaryOf('s1'), isNull);
    });

    test('forget 丢弃摘要', () async {
      final Compactor compactor = Compactor(keepRecent: 1);
      final Session session = _session(2);
      await compactor.compact(session, (_, __) async => '摘要');

      compactor.forget('s1');
      expect(compactor.summaryOf('s1'), isNull);
    });

    test('keepRecent 为负时构造抛错', () {
      expect(() => Compactor(keepRecent: -1), throwsArgumentError);
    });
  });

  test('provideCompaction 作为 compaction 服务提供', () {
    final ctx = Context.root();
    final Compactor compactor = provideCompaction(ctx);
    expect(identical(ctx.require<Compactor>('compaction'), compactor), isTrue);
    ctx.dispose();
  });
}
