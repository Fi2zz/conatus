import 'dart:io';
import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

Session _session(String id) {
  final Session session = Session(id: id);
  session.append(kUserMessageEvent, data: <String, Object?>{'text': '你好'});
  session.append(kAssistantMessageEvent, data: <String, Object?>{'text': '在的'});
  session.append(kToolResultEvent,
      data: <String, Object?>{'name': 'get_time', 'content': '12:00'});
  return session;
}

void main() {
  group('RecoveryService — 内存', () {
    test('snapshot / restore 往返', () async {
      final RecoveryService recovery =
          RecoveryService(store: MemorySnapshotStore());
      final Session session = _session('s1');

      await recovery.snapshot(session);
      final Session restored = await recovery.restore('s1');

      expect(restored.id, 's1');
      expect(restored.length, 3);
      expect(restored.events.map((SessionEvent e) => e.type), <String>[
        kUserMessageEvent,
        kAssistantMessageEvent,
        kToolResultEvent,
      ]);
      expect(await recovery.list(), <String>['s1']);
    });

    test('load 缺失抛 not-found；delete 生效', () async {
      final RecoveryService recovery =
          RecoveryService(store: MemorySnapshotStore());
      await expectLater(
        recovery.load('nope'),
        throwsA(isA<RecoveryException>()
            .having((RecoveryException e) => e.code, 'code', 'not-found')),
      );

      await recovery.snapshot(_session('s2'));
      await recovery.delete('s2');
      expect(await recovery.list(), isEmpty);
    });

    test('快照版本不符抛 unsupported-version', () {
      const SessionSnapshot stale = SessionSnapshot(
        sessionId: 's1',
        events: <SessionEvent>[],
        version: 99,
      );
      expect(
        () => SessionSnapshot.fromJson(stale.toJson()),
        throwsA(isA<RecoveryException>().having(
            (RecoveryException e) => e.code, 'code', 'unsupported-version')),
      );
    });
  });

  group('DatabaseSnapshotStore', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('conatus-snapshot-'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('落盘后可由新 hub 恢复', () async {
      final Database first = Database(defaultBackend: 'json')
        ..register('json', JsonDatabaseBackend(dir: dir.path));
      await RecoveryService(store: DatabaseSnapshotStore(first))
          .snapshot(_session('s1'));

      final Database reopened = Database(defaultBackend: 'json')
        ..register('json', JsonDatabaseBackend(dir: dir.path));
      final RecoveryService recovery =
          RecoveryService(store: DatabaseSnapshotStore(reopened));

      expect(await recovery.list(), <String>['s1']);
      expect((await recovery.restore('s1')).length, 3);
    });

    test('list / delete', () async {
      final Database db = Database(defaultBackend: 'json')
        ..register('json', JsonDatabaseBackend(dir: dir.path));
      final RecoveryService recovery =
          RecoveryService(store: DatabaseSnapshotStore(db));

      await recovery.snapshot(_session('a'));
      await recovery.snapshot(_session('b'));
      expect((await recovery.list())..sort(), <String>['a', 'b']);
      await recovery.delete('a');
      expect(await recovery.list(), <String>['b']);
    });
  });

  group('provideRecovery', () {
    test('无 database 时用内存实现', () {
      final Context ctx = Context.root();
      final RecoveryService recovery = provideRecovery(ctx);
      expect(recovery.store, isA<MemorySnapshotStore>());
      expect(identical(ctx.recovery, recovery), isTrue);
      ctx.dispose();
    });

    test('有 database 时用 Database 后端', () {
      final Context ctx = Context.root();
      provideDatabase(ctx, defaultBackend: 'json');
      provideDatabaseJson(ctx, dir: Directory.systemTemp.path);
      final RecoveryService recovery = provideRecovery(ctx);
      expect(recovery.store, isA<DatabaseSnapshotStore>());
      ctx.dispose();
    });
  });
}
