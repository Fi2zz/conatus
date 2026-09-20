import 'dart:io';
import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

PromptVariant _variant(String id, {String? parentId, double? score}) =>
    PromptVariant(
      id: id,
      sectionName: 'persona',
      text: '文本 $id',
      reason: '原因 $id',
      parentId: parentId,
      score: score,
      createdAt: DateTime.utc(2026),
    );

void main() {
  group('PromptVariant', () {
    test('JSON 往返一致（含 score 与 parentId）', () {
      final PromptVariant variant = _variant('v1', parentId: 'p0', score: 0.8);
      final PromptVariant restored = PromptVariant.fromJson(variant.toJson());
      expect(restored.id, 'v1');
      expect(restored.sectionName, 'persona');
      expect(restored.text, '文本 v1');
      expect(restored.reason, '原因 v1');
      expect(restored.parentId, 'p0');
      expect(restored.score, 0.8);
      expect(restored.createdAt, DateTime.utc(2026));
    });

    test('JSON 往返一致（无 score 与 parentId）', () {
      final PromptVariant variant = _variant('v2');
      final PromptVariant restored = PromptVariant.fromJson(variant.toJson());
      expect(restored.parentId, isNull);
      expect(restored.score, isNull);
    });

    test('copyWith 设置与清除 score', () {
      final PromptVariant variant = _variant('v1');
      final PromptVariant scored = variant.copyWith(score: 0.9);
      expect(scored.score, 0.9);
      expect(scored.id, 'v1');
      final PromptVariant cleared = scored.copyWith();
      expect(cleared.score, isNull);
    });
  });

  group('PromptStore', () {
    test('无 database 时纯内存存档', () async {
      final PromptStore store = PromptStore();
      await store.save(_variant('a'));
      await store.save(_variant('b'));
      expect(store.all.map((PromptVariant v) => v.id), <String>['a', 'b']);
      expect(store.find('a')?.text, '文本 a');
      expect(store.find('nope'), isNull);
    });

    test('经 JsonDatabaseBackend 持久化并恢复', () async {
      final Directory dir = await Directory.systemTemp.createTemp('evolver');
      addTearDown(() => dir.delete(recursive: true));
      final DatabaseBackend backend = JsonDatabaseBackend(dir: dir.path);
      final Database db1 = Database(defaultBackend: 'json')
        ..register('json', backend);
      final PromptStore store = PromptStore(database: db1);
      await store.save(_variant('a'));
      await store.save(_variant('b', parentId: 'a', score: 0.7));

      // 新 Database 实例模拟重启，走同一后端介质。
      final Database db2 = Database(defaultBackend: 'json')
        ..register('json', backend);
      final PromptStore restored = PromptStore(database: db2);
      await restored.load();
      expect(restored.all.map((PromptVariant v) => v.id), <String>['a', 'b']);
      expect(restored.find('b')?.parentId, 'a');
      expect(restored.find('b')?.score, 0.7);
    });

    test('损坏的存档记录跳过', () async {
      final Directory dir = await Directory.systemTemp.createTemp('evolver');
      addTearDown(() => dir.delete(recursive: true));
      final Database db = Database(defaultBackend: 'json')
        ..register('json', JsonDatabaseBackend(dir: dir.path));
      final PromptStore store = PromptStore(database: db);
      await store.save(_variant('a'));
      final DatabaseUnit unit = db.get('prompt_evolver')!;
      await unit.put(PromptStore.key, <Object?>[
        <String, Object?>{'parentId': 42}, // 类型错误 → 跳过
        'garbage', // 非 Map → 跳过
        <String, Object?>{
          'id': 'b',
          'sectionName': 'persona',
          'text': 'ok',
          'reason': 'r',
          'createdAt': '2026-01-01T00:00:00.000Z',
        },
      ]);

      final PromptStore restored = PromptStore(database: db);
      await restored.load();
      expect(restored.all.map((PromptVariant v) => v.id), <String>['b']);
    });
  });
}
