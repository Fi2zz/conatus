import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

Matcher _dbError(String code) => isA<DatabaseException>()
    .having((DatabaseException e) => e.code, 'code', code);

void main() {
  late Directory dir;
  late JsonDatabaseBackend backend;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-db-');
    backend = JsonDatabaseBackend(dir: dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('Database — 后端注册', () {
    test('register / backendNames / backend；重名与空名抛错', () {
      final Database db = Database()..register('a', backend);

      expect(db.backendNames, <String>['a']);
      expect(identical(db.backend('a'), backend), isTrue);
      expect(() => db.register('a', backend),
          throwsA(_dbError('duplicate-backend')));
      expect(
          () => db.register('', backend), throwsA(_dbError('invalid-backend')));
      expect(() => db.backend('nope'), throwsA(_dbError('backend-not-found')));
    });

    test('撤销函数注销后端（幂等）', () {
      final Database db = Database();
      final Disposer off = db.register('a', backend);

      off();
      off();
      expect(db.backendNames, isEmpty);
    });
  });

  group('Database — 单元', () {
    test('open 载入空表；put/has/get/keys/entries', () async {
      final Database db = Database(defaultBackend: 'json')
        ..register('json', backend);
      final DatabaseUnit unit = await db.open('u');

      expect(unit.length, 0);
      await unit.put('k', 'v');

      expect(unit.has('k'), isTrue);
      expect(unit.get('k'), 'v');
      expect(unit.keys, <String>['k']);
      expect(unit.entries(), <String, Object?>{'k': 'v'});
      expect(db.units, <String>['u']);
    });

    test('重复 open 与空单元名抛错；close 后可重开', () async {
      final Database db = Database(defaultBackend: 'json')
        ..register('json', backend);
      final DatabaseUnit unit = await db.open('u');

      await expectLater(db.open('u'), throwsA(_dbError('already-open')));
      await expectLater(db.open(''), throwsA(_dbError('invalid-unit')));

      expect(db.close('u'), isTrue);
      expect(unit.closed, isTrue);
      expect(db.close('u'), isFalse);
      expect((await db.open('u')).closed, isFalse);
    });

    test('delete 返回是否存在', () async {
      final Database db = Database(defaultBackend: 'json')
        ..register('json', backend);
      final DatabaseUnit unit = await db.open('u');
      await unit.put('k', 'v');

      expect(await unit.delete('k'), isTrue);
      expect(await unit.delete('k'), isFalse);
      expect(unit.has('k'), isFalse);
    });

    test('onChange 在落盘后广播 put / deleted', () async {
      final Database db = Database(defaultBackend: 'json')
        ..register('json', backend);
      final DatabaseUnit unit = await db.open('u');
      final List<DatabaseChange> changes = <DatabaseChange>[];
      unit.onChange(changes.add);

      await unit.put('k', 1);
      await unit.delete('k');

      expect(changes, hasLength(2));
      expect(changes[0].kind, DatabaseChangeKind.put);
      expect(changes[0].unit, 'u');
      expect(changes[0].key, 'k');
      expect(changes[0].value, 1);
      expect(changes[1].kind, DatabaseChangeKind.deleted);
      expect(changes[1].value, isNull);
    });

    test('关闭后写入抛错', () async {
      final Database db = Database(defaultBackend: 'json')
        ..register('json', backend);
      final DatabaseUnit unit = await db.open('u');
      unit.close();

      await expectLater(unit.put('k', 'v'), throwsA(_dbError('unit-closed')));
    });

    test('后端不唯一且未指定路由时抛 no-backend', () async {
      final Database db = Database()
        ..register('a', JsonDatabaseBackend(dir: dir.path))
        ..register('b', JsonDatabaseBackend(dir: dir.path));

      await expectLater(db.open('u'), throwsA(_dbError('no-backend')));
      expect((await db.open('u', backend: 'b')).name, 'u');
    });
  });

  group('JsonDatabaseBackend', () {
    test('写入落盘后可由新 hub 打开读回', () async {
      final Database first = Database(defaultBackend: 'json')
        ..register('json', backend);
      final DatabaseUnit unit = await first.open('profile');
      await unit.put('name', '助手');
      await unit.put('age', 80);

      final Database reopened = Database(defaultBackend: 'json')
        ..register('json', JsonDatabaseBackend(dir: dir.path));
      final DatabaseUnit loaded = await reopened.open('profile');

      expect(loaded.get('name'), '助手');
      expect(loaded.get('age'), 80);
    });

    test('deleteUnit 删除文件', () async {
      await backend.save('u', <String, Object?>{'k': 'v'});
      expect(File('${dir.path}/u.json').existsSync(), isTrue);

      await backend.deleteUnit('u');
      expect(File('${dir.path}/u.json').existsSync(), isFalse);
    });

    test('非对象的合法 JSON 判为 malformed-medium', () async {
      File('${dir.path}/u.json').writeAsStringSync('[1,2,3]');
      final Database db = Database(defaultBackend: 'json')
        ..register('json', backend);

      await expectLater(db.open('u'), throwsA(_dbError('malformed-medium')));
    });
  });

  group('provideDatabase / provideDatabaseJson', () {
    test('提供 database 服务并注册 JSON 后端', () async {
      final ctx = Context.root();
      final Database hub = provideDatabase(ctx, defaultBackend: 'json');
      provideDatabaseJson(ctx, dir: dir.path);

      expect(identical(ctx.require<Database>('database'), hub), isTrue);
      expect(hub.backendNames, <String>['json']);

      final DatabaseUnit unit = await hub.open('u');
      ctx.dispose();
      expect(unit.closed, isTrue);
    });
  });
}
