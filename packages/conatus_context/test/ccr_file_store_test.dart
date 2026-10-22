import 'dart:io';

import 'package:conatus_context/conatus_context.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late LocalFileSystem fs;
  late CcrFileStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ctx_ccr');
    fs = LocalFileSystem();
    store = CcrFileStore(fs: fs, dir: tmp.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('往返字节相等，重启后可读', () async {
    final String id = await store.put('原文\nline2');
    final CcrFileStore second = CcrFileStore(fs: fs, dir: tmp.path);
    expect(await second.get(id), '原文\nline2');
  });

  test('内容被篡改视为未命中', () async {
    final String id = await store.put('original');
    await fs.writeText(await fs.resolve('${tmp.path}/$id.txt'), 'tampered');
    expect(await CcrFileStore(fs: fs, dir: tmp.path).get(id), isNull);
  });

  test('目录不存在时按空存储启动，put 时创建', () async {
    final CcrFileStore s = CcrFileStore(fs: fs, dir: '${tmp.path}/missing');
    expect(s.length, 0);
    final String id = await s.put('x');
    expect(await s.get(id), 'x');
  });

  test('TTL 过期视为未命中', () async {
    DateTime now = DateTime(2026);
    final CcrFileStore s = CcrFileStore(
      fs: fs,
      dir: tmp.path,
      ttl: const Duration(seconds: 10),
      now: () => now,
    );
    final String id = await s.put('x');
    now = now.add(const Duration(seconds: 11));
    expect(await s.get(id), isNull);
  });

  test('超过容量淘汰最久未访问项', () async {
    DateTime now = DateTime(2026);
    final CcrFileStore s = CcrFileStore(
      fs: fs,
      dir: tmp.path,
      maxEntries: 2,
      now: () => now,
    );
    final String a = await s.put('a');
    now = now.add(const Duration(seconds: 1));
    final String b = await s.put('b');
    now = now.add(const Duration(seconds: 1));
    await s.get(a);
    now = now.add(const Duration(seconds: 1));
    final String c = await s.put('c');
    expect(await s.get(b), isNull);
    expect(await s.get(a), 'a');
    expect(await s.get(c), 'c');
    final List<String> files = (await fs.listDir(await fs.resolve(tmp.path)))
        .map((FsDirEntry entry) => entry.name)
        .where((String name) => name.endsWith('.txt'))
        .toList();
    expect(files, containsAll(<String>['$a.txt', '$c.txt']));
    expect(files, isNot(contains('$b.txt')));
  });

  test('clear 后条目与文件都消失', () async {
    final String id = await store.put('x');
    await store.clear();
    expect(store.length, 0);
    expect(await store.get(id), isNull);
  });
}
