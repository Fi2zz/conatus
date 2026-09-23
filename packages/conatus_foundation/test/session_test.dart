import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('Session', () {
    test('append 从 0 起分配 seq 并携带负载', () {
      final Session session = Session(id: 's1');

      final SessionEvent first = session.append('user/message', data: 'hi');
      final SessionEvent second = session.append('assistant/message');

      expect(first.seq, 0);
      expect(second.seq, 1);
      expect(first.type, 'user/message');
      expect(first.data, 'hi');
      expect(session.length, 2);
      expect(session.events.last, same(second));
      expect(session.createdAt.isAfter(DateTime(2000)), isTrue);
    });

    test('onEvent 监听后续追加，撤销后不再收到', () {
      final Session session = Session(id: 's1');
      final List<int> seen = <int>[];
      final Disposer off = session.onEvent((SessionEvent e) => seen.add(e.seq));

      session.append('a');
      off();
      session.append('b');

      expect(seen, <int>[0]);
    });

    test('close 拒绝后续追加并通知关闭监听器（幂等）', () {
      final Session session = Session(id: 's1');
      var closed = 0;
      session.onClose(() => closed++);

      session.close();
      session.close();

      expect(session.closed, isTrue);
      expect(closed, 1);
      expect(() => session.append('a'), throwsStateError);
    });

    test('已关闭时 onClose 立即回调', () {
      final Session session = Session(id: 's1')..close();
      var closed = 0;
      session.onClose(() => closed++);
      expect(closed, 1);
    });

    test('seed 事件续接 seq 与创建时间', () {
      final DateTime t = DateTime(2020);
      final Session session = Session(id: 's1', seed: <SessionEvent>[
        SessionEvent(seq: 0, type: 'a', time: t),
        SessionEvent(seq: 1, type: 'b', time: t),
      ]);

      expect(session.length, 2);
      expect(session.createdAt, t);
      expect(session.append('c').seq, 2);
    });
  });

  group('SessionStore — 内存', () {
    test('create / get / ids，重复 id 抛 StateError', () {
      final SessionStore store = SessionStore();

      final Session session = store.create(id: 'a');

      expect(store.get('a'), same(session));
      expect(store.ids, <String>['a']);
      expect(() => store.create(id: 'a'), throwsStateError);
    });

    test('create 缺省 id 生成 session_<uuid>，两次互不相同', () {
      final SessionStore store = SessionStore();

      final Session first = store.create();
      final Session second = store.create();

      expect(
        first.id,
        matches(r'^session_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-'
            r'[0-9a-f]{12}$'),
      );
      expect(first.id, isNot(second.id));
    });

    test('close 从活跃集移除并关闭会话', () async {
      final SessionStore store = SessionStore();
      final Session session = store.create(id: 'a');

      expect(store.close('a'), isTrue);
      expect(session.closed, isTrue);
      expect(store.get('a'), isNull);
      expect(store.close('a'), isFalse);
    });
  });

  group('SessionStore — JSONL 持久化', () {
    late Directory dir;
    late JsonlSessionPersistence persistence;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('conatus-session-test-');
      persistence = JsonlSessionPersistence(dir: dir.path);
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('追加落盘后可由新仓库 open 回来', () async {
      final SessionStore store = SessionStore(persistence: persistence);
      final Session session = store.create(id: 's1');
      session.append('user/message', data: <String, Object?>{'text': '你好'});
      await store.flush();

      final SessionStore reopened = SessionStore(persistence: persistence);
      final Session loaded = await reopened.open('s1');

      expect(loaded.length, 1);
      expect(loaded.events.single.type, 'user/message');
      expect(
        (loaded.events.single.data! as Map<String, Object?>)['text'],
        '你好',
      );
      expect(await reopened.persistedIds(), <String>['s1']);
    });

    test('同一轮连续 append 不丢事件（首写并发建目录）', () async {
      final SessionStore store = SessionStore(persistence: persistence);
      final Session session = store.create(id: 'burst');
      session.append('user/message', data: <String, Object?>{'text': '说普通话'});
      session
          .append('assistant/message', data: <String, Object?>{'text': '好的'});
      await store.flush();

      final SessionStore reopened = SessionStore(persistence: persistence);
      final Session loaded = await reopened.open('burst');

      expect(
        loaded.events.map((SessionEvent e) => e.type),
        <String>['user/message', 'assistant/message'],
      );
    });

    test('open 未持久化的 id 得到空会话，随后追加会落盘', () async {
      final SessionStore store = SessionStore(persistence: persistence);
      final Session session = await store.open('fresh');
      expect(session.length, 0);

      session.append('a');
      await store.flush();

      final SessionStore reopened = SessionStore(persistence: persistence);
      expect((await reopened.open('fresh')).length, 1);
    });

    test('remove 关闭会话并删除持久化数据', () async {
      final SessionStore store = SessionStore(persistence: persistence);
      store.create(id: 's1').append('a');
      await store.flush();

      expect(await store.remove('s1'), isTrue);
      expect(store.get('s1'), isNull);
      expect(await persistence.list(), isEmpty);
    });
  });

  group('provideSessions', () {
    test('作为 sessions 服务提供，并复用已提供的持久化', () {
      final ctx = Context.root();
      final SessionPersistence persistence =
          JsonlSessionPersistence(dir: '/tmp/unused');
      provideSessionPersistence(ctx, persistence: persistence);

      final SessionStore store = provideSessions(ctx);

      expect(identical(store, ctx.require<SessionStore>('sessions')), isTrue);
      expect(
        identical(
          ctx.require<SessionPersistence>('sessionPersistence'),
          persistence,
        ),
        isTrue,
      );
      ctx.dispose();
    });
  });
}
