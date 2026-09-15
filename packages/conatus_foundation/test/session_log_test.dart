import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 用一条 `e<i>` 事件序列填充 `log` 的 `sessionId` 会话。
Future<List<SessionEvent>> seed(SessionLog log, String sessionId, int count) async {
  final DateTime base = DateTime(2024);
  final List<SessionEvent> events = <SessionEvent>[
    for (int i = 0; i < count; i++)
      SessionEvent.create(
        sessionId: sessionId,
        type: 'e$i',
        seq: i,
        time: base.add(Duration(minutes: i)),
      ),
  ];
  for (final SessionEvent event in events) {
    await log.append(event);
  }
  return events;
}

Future<List<String>> typesOf(SessionLog log, String sessionId) async =>
    <String>[await for (final SessionEvent e in log.read(sessionId)) e.type];

/// 三种后端共用同一套行为契约测试。
void logSuite(String name, SessionLog Function(Directory dir) build) {
  group(name, () {
    late Directory dir;
    late SessionLog log;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('conatus-session-log-');
      log = build(dir);
    });

    tearDown(() async {
      await log.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('append 按 seq 读回；缺 sessionId 抛 ArgumentError', () async {
      await seed(log, 's1', 3);

      final List<SessionEvent> events = await log.read('s1').toList();

      expect(events.map((SessionEvent e) => e.type), <String>['e0', 'e1', 'e2']);
      expect(events.map((SessionEvent e) => e.seq), <int>[0, 1, 2]);
      expect(await log.read('nope').toList(), isEmpty);
      await expectLater(
        log.append(SessionEvent(seq: 0, type: 'x', time: DateTime(2024))),
        throwsArgumentError,
      );
    });

    test('append 覆盖入参 seq 并返回落定事件', () async {
      final SessionEvent first = await log.append(
        SessionEvent.create(sessionId: 's1', type: 'a', seq: 99),
      );
      final SessionEvent second = await log.append(
        SessionEvent.create(sessionId: 's1', type: 'b', seq: 42),
      );

      expect(first.seq, 0);
      expect(second.seq, 1);
      expect(first.id, isNotNull);
      expect(
        (await log.read('s1').toList()).map((SessionEvent e) => e.seq),
        <int>[0, 1],
      );
    });

    test('read 支持闭区间时间窗过滤', () async {
      final List<SessionEvent> events = await seed(log, 's1', 3);
      final DateTime mid = events[1].time;

      final List<SessionEvent> window = await log
          .read('s1', from: mid, to: mid)
          .toList();

      expect(window.map((SessionEvent e) => e.type), <String>['e1']);
      expect(
        (await log.read('s1', from: mid).toList())
            .map((SessionEvent e) => e.type),
        <String>['e1', 'e2'],
      );
    });

    test('fork 复制截止事件（含）的前缀，源会话不受影响', () async {
      final List<SessionEvent> events = await seed(log, 's1', 3);

      final String forkId = await log.fork('s1', events[1].id!);

      expect(forkId, 's1-fork-1');
      expect(await typesOf(log, forkId), <String>['e0', 'e1']);
      final List<SessionEvent> forked = await log.read(forkId).toList();
      expect(forked.map((SessionEvent e) => e.seq), <int>[0, 1]);
      expect(forked.map((SessionEvent e) => e.id), <String?>[
        events[0].id,
        events[1].id,
      ]);
      expect(forked.every((SessionEvent e) => e.sessionId == forkId), isTrue);
      expect(await typesOf(log, 's1'), <String>['e0', 'e1', 'e2']);
    });

    test('fork 支持显式新 id，计数器按源会话递增', () async {
      final List<SessionEvent> events = await seed(log, 's1', 2);

      expect(await log.fork('s1', events[0].id!, newId: 'custom'), 'custom');
      expect(await typesOf(log, 'custom'), <String>['e0']);
      expect(await log.fork('s1', events[0].id!), 's1-fork-1');
    });

    test('fork 不存在的事件抛 StateError', () async {
      await seed(log, 's1', 2);
      await expectLater(log.fork('s1', 'nope'), throwsStateError);
    });

    test('replay 按 seq 顺序回调，日志不被改写', () async {
      await seed(log, 's1', 3);
      final List<String> seen = <String>[];

      await log.replay('s1', (SessionEvent e) => seen.add(e.type));

      expect(seen, <String>['e0', 'e1', 'e2']);
      expect(await typesOf(log, 's1'), <String>['e0', 'e1', 'e2']);
    });

    test('list 列出全部会话 id（升序）', () async {
      await seed(log, 's2', 1);
      await seed(log, 's1', 1);

      expect(await log.list(), <String>['s1', 's2']);
    });
  });
}

void main() {
  logSuite('InMemorySessionLog', (Directory dir) => InMemorySessionLog());

  logSuite('PersistenceSessionLog', (Directory dir) =>
      PersistenceSessionLog(JsonlSessionPersistence(dir: dir.path)));

  logSuite('DatabaseSessionLog', (Directory dir) {
    final Database hub = Database(defaultBackend: 'json');
    hub.register('json', JsonDatabaseBackend(dir: dir.path));
    return DatabaseSessionLog(hub);
  });

  group('provideSessionLog', () {
    test('无后端服务时回退内存实现，ctx.sessionLog 可见且释放时关闭', () {
      final Context ctx = Context.root();

      final SessionLog log = provideSessionLog(ctx);

      expect(log, isA<InMemorySessionLog>());
      expect(identical(ctx.sessionLog, log), isTrue);
      ctx.dispose();
      expect((log as InMemorySessionLog).closed, isTrue);
    });

    test('有 sessionPersistence 服务时用追加式后端', () {
      final Context ctx = Context.root();
      provideSessionPersistence(
        ctx,
        persistence: JsonlSessionPersistence(dir: '/tmp/unused-log'),
      );

      expect(provideSessionLog(ctx), isA<PersistenceSessionLog>());
      ctx.dispose();
    });

    test('有 database 服务（已注册后端）时用 Database 后端', () {
      final Context ctx = Context.root();
      final Directory dir =
          Directory.systemTemp.createTempSync('conatus-session-log-db-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final Database hub = Database(defaultBackend: 'json');
      hub.register('json', JsonDatabaseBackend(dir: dir.path));
      provideDatabase(ctx, database: hub);

      expect(provideSessionLog(ctx), isA<DatabaseSessionLog>());
      ctx.dispose();
    });

    test('显式传入的日志优先于后端探测', () {
      final Context ctx = Context.root();
      final Directory dir =
          Directory.systemTemp.createTempSync('conatus-session-log-explicit-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final Database hub = Database(defaultBackend: 'json');
      hub.register('json', JsonDatabaseBackend(dir: dir.path));
      provideDatabase(ctx, database: hub);
      final InMemorySessionLog explicit = InMemorySessionLog();

      expect(provideSessionLog(ctx, log: explicit), same(explicit));
      expect(identical(ctx.sessionLog, explicit), isTrue);
      ctx.dispose();
    });
  });
}
