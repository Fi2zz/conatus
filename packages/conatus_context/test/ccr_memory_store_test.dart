import 'package:conatus_context/conatus_context.dart';
import 'package:test/test.dart';

void main() {
  test('内存存储往返字节相等并计数命中', () async {
    final CcrMemoryStore store = CcrMemoryStore();
    final String id = await store.put('原文\n第二行');
    expect(await store.get(id), '原文\n第二行');
    expect(store.hits, 1);
    expect(store.length, 1);
    final CcrEntry? entry = await store.stat(id);
    expect(entry!.chars, '原文\n第二行'.length);
    expect(entry.hits, 1);
  });

  test('TTL 过期视为未命中', () async {
    DateTime now = DateTime(2026);
    final CcrMemoryStore store = CcrMemoryStore(
      ttl: const Duration(seconds: 10),
      now: () => now,
    );
    final String id = await store.put('x');
    now = now.add(const Duration(seconds: 11));
    expect(await store.get(id), isNull);
    expect(store.length, 0);
  });

  test('超过容量淘汰最久未访问项', () async {
    final CcrMemoryStore store = CcrMemoryStore(maxEntries: 2);
    final String a = await store.put('a');
    final String b = await store.put('b');
    await store.get(a);
    final String c = await store.put('c');
    expect(await store.get(b), isNull);
    expect(await store.get(a), 'a');
    expect(await store.get(c), 'c');
  });

  test('remove 与 clear 幂等', () async {
    final CcrMemoryStore store = CcrMemoryStore();
    final String id = await store.put('x');
    await store.remove(id);
    await store.remove(id);
    expect(await store.get(id), isNull);
    await store.put('y');
    await store.clear();
    await store.clear();
    expect(store.length, 0);
  });
}
