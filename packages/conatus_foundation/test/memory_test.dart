import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryStore — 写入与召回', () {
    test('remember 增加条目并通知 onChange', () async {
      final MemoryStore store = MemoryStore();
      var changes = 0;
      store.onChange(() => changes++);

      final MemoryEntry entry = await store.remember('用户喜欢京剧', tags: {'偏好'});

      expect(entry.text, '用户喜欢京剧');
      expect(entry.tags, <String>{'偏好'});
      expect(store.length, 1);
      expect(store.entries.single.id, entry.id);
      expect(changes, 1);
    });

    test('按关键词打分排序，高分在前', () async {
      final MemoryStore store = MemoryStore();
      await store.remember('咖啡 拿铁');
      await store.remember('咖啡 咖啡 咖啡 甜点');

      final List<MemoryEntry> hits = store.recall('咖啡 甜点');

      expect(hits, hasLength(2));
      expect(hits.first.text, '咖啡 咖啡 咖啡 甜点');
    });

    test('中文按二元组匹配', () async {
      final MemoryStore store = MemoryStore();
      await store.remember('用户喜欢京剧');
      await store.remember('用户喜欢旅游');

      expect(store.recall('京剧').single.text, '用户喜欢京剧');
    });

    test('标签参与召回', () async {
      final MemoryStore store = MemoryStore();
      await store.remember('无关正文', tags: {'preference'});

      expect(store.recall('preference').single.text, '无关正文');
    });

    test('空查询与 limit<=0 返回空', () async {
      final MemoryStore store = MemoryStore();
      await store.remember('你好');

      expect(store.recall('   '), isEmpty);
      expect(store.recall('你好', limit: 0), isEmpty);
    });

    test('forget 删除条目', () async {
      final MemoryStore store = MemoryStore();
      final MemoryEntry entry = await store.remember('x');

      expect(await store.forget(entry.id), isTrue);
      expect(store.length, 0);
      expect(await store.forget(entry.id), isFalse);
    });

    test('容量治理逐出最旧条目', () async {
      final MemoryStore store = MemoryStore(maxEntries: 2);
      final MemoryEntry first = await store.remember('a');
      final MemoryEntry second = await store.remember('b');
      final MemoryEntry third = await store.remember('c');

      expect(store.length, 2);
      expect(
        store.entries.map((MemoryEntry e) => e.id),
        <String>[second.id, third.id],
      );
      expect(store.entries.any((MemoryEntry e) => e.id == first.id), isFalse);
    });

    test('maxEntries 为负时构造抛错', () {
      expect(() => MemoryStore(maxEntries: -1), throwsArgumentError);
    });
  });

  group('JsonMemoryBackend', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('conatus-memory-'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('落盘后可由新 store 载回', () async {
      final JsonMemoryBackend backend =
          JsonMemoryBackend(file: File('${dir.path}/memory.json'));
      final MemoryStore store = MemoryStore(backend: backend);
      await store.remember('hello', tags: {'t'});

      final MemoryStore reopened = MemoryStore(backend: backend);
      await reopened.load();

      expect(reopened.length, 1);
      expect(reopened.entries.single.text, 'hello');
      expect(reopened.entries.single.tags, <String>{'t'});
    });
  });

  group('provideMemory', () {
    test('作为 memory 服务提供', () {
      final ctx = Context.root();
      final MemoryStore store = provideMemory(ctx);
      expect(identical(ctx.require<MemoryStore>('memory'), store), isTrue);
      ctx.dispose();
    });
  });
}
