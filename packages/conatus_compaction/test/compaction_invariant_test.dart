import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

Session _plain(int events) {
  final Session session = Session(id: 's1');
  for (int i = 0; i < events; i++) {
    session.append('e$i');
  }
  return session;
}

void _start(Session session, String id) => session.append(kCompactionStartEvent,
    data: <String, Object?>{'compactionId': id, 'keepRecent': 1});

void _summary(Session session, String id, Object? shadowed) =>
    session.append(kCompactionSummaryEvent, data: <String, Object?>{
      'compactionId': id,
      'summary': '摘要',
      'shadowedSeqs': shadowed,
      'kept': 1,
    });

void _end(Session session, String id, {String? error}) =>
    session.append(kCompactionEndEvent, data: <String, Object?>{
      'compactionId': id,
      if (error != null) 'error': error,
    });

void main() {
  group('checkCompactionInvariant', () {
    test('没有压缩事件的日志通过', () {
      expect(checkCompactionInvariant(_plain(3).events), isEmpty);
    });

    test('完整的一次压缩通过', () {
      final Session session = _plain(3)
        ..append(kCompactionStartEvent, data: <String, Object?>{
          'compactionId': 'c1',
          'keepRecent': 2,
        });
      _summary(session, 'c1', <int>[0]);
      _end(session, 'c1');

      expect(checkCompactionInvariant(session.events), isEmpty);
    });

    test('失败的压缩（end 带 error）通过', () {
      final Session session = _plain(3);
      _start(session, 'c1');
      _end(session, 'c1', error: 'boom');

      expect(checkCompactionInvariant(session.events), isEmpty);
    });

    test('start 缺少 compactionId', () {
      final Session session = _plain(1)
        ..append(kCompactionStartEvent, data: <String, Object?>{});
      _summary(session, '', <int>[0]);
      _end(session, '');

      expect(checkCompactionInvariant(session.events),
          contains(contains('缺少 compactionId')));
    });

    test('没有 end 收尾', () {
      final Session session = _plain(3);
      _start(session, 'c1');

      expect(checkCompactionInvariant(session.events),
          contains(contains('没有 $kCompactionEndEvent 收尾')));
    });

    test('start 未收尾又开了一次', () {
      final Session session = _plain(3);
      _start(session, 'c1');
      _start(session, 'c2');

      expect(checkCompactionInvariant(session.events),
          contains(contains('身份 c1 的压缩还没有收尾')));
    });

    test('summary 身份与进行中的压缩不一致', () {
      final Session session = _plain(3);
      _start(session, 'c1');
      _summary(session, 'c2', <int>[0]);
      _end(session, 'c1', error: 'boom');

      expect(checkCompactionInvariant(session.events),
          contains(contains('与进行中的压缩 c1 不一致')));
    });

    test('一次压缩里出现两个 summary', () {
      final Session session = _plain(3);
      _start(session, 'c1');
      _summary(session, 'c1', <int>[0]);
      _summary(session, 'c1', <int>[0, 1]);
      _end(session, 'c1');

      expect(checkCompactionInvariant(session.events),
          contains(contains('在一次压缩里重复出现')));
    });

    test('成功的 end 之前没有 summary', () {
      final Session session = _plain(3);
      _start(session, 'c1');
      _end(session, 'c1');

      expect(checkCompactionInvariant(session.events),
          contains(contains('没有 $kCompactionSummaryEvent')));
    });

    test('折叠区间不是日志开头的一段', () {
      final Session session = _plain(3);
      _start(session, 'c1');
      _summary(session, 'c1', <int>[1, 2]);
      _end(session, 'c1');

      expect(checkCompactionInvariant(session.events),
          contains(contains('折叠的不是日志开头的一段')));
    });

    test('缺少或非法的 shadowedSeqs', () {
      final Session session = _plain(2);
      _start(session, 'c1');
      _summary(session, 'c1', <Object?>['x']);
      _end(session, 'c1');

      expect(checkCompactionInvariant(session.events),
          contains(contains('缺少 shadowedSeqs')));
    });
  });

  test('assertCompactionInvariant 在违规时抛错', () {
    final Session session = _plain(1);
    _start(session, 'c1');

    expect(() => assertCompactionInvariant(session.events), throwsStateError);
    _end(session, 'c1', error: 'boom');
    expect(() => assertCompactionInvariant(session.events), returnsNormally);
  });
}
