/// CheckpointStore（delta 版）：base 全量 + 差量、prune、list、旧格式兼容。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

import 'checkpoint_fixtures.dart';

/// 强制文件的 mtime/size 变化（写不同内容即可触发 delta 复制）。
void _touch(String root, String rel, String content) =>
    writeWorkspace(root, rel, content);

void main() {
  test('turn 0 全量 base（含 mtime/size），跳过排除项，写 manifest', () async {
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore(
      ignore: const <String>['node_modules'],
    );
    writeWorkspace(root, 'lib/main.dart', 'void main() {}');
    writeWorkspace(root, 'README.md', '# hi');
    writeWorkspace(root, '.git/config', 'not-snapshotted');
    writeWorkspace(root, 'node_modules/pkg/index.js', 'skip');
    writeWorkspace(root, '.conatus/secret.json', 'skip');

    await store.snapshot('s1', 0, lastEventId: 'ev-0');

    final List<CheckpointInfo> infos = store.list('s1');
    expect(infos.single.turn, 0);
    expect(infos.single.files, 2);
    final CheckpointManifest base = store.manifestOf('s1', 0);
    expect(base.isDelta, isFalse);
    expect(base.lastEventId, 'ev-0');
    expect(
      base.files.map((CheckpointFileEntry e) => e.path),
      unorderedEquals(<String>['lib/main.dart', 'README.md']),
    );
    expect(base.files.every((CheckpointFileEntry e) => e.size > 0), isTrue);
  });

  test('turn 1 差量：只存变化/新增文件，deleted 记录删除', () async {
    final (ArchiveCheckpointStore store, String root, String projectDir) =
        createArchiveStore();
    writeWorkspace(root, 'a.txt', 'v0');
    writeWorkspace(root, 'b.txt', 'b0');
    await store.snapshot('s1', 0);

    _touch(root, 'a.txt', 'v1'); // 变化
    writeWorkspace(root, 'c.txt', 'new'); // 新增
    File('$root${pathSep}b.txt').deleteSync(); // 删除
    await store.snapshot('s1', 1, lastEventId: 'ev-1');

    final CheckpointManifest delta = store.manifestOf('s1', 1);
    expect(delta.isDelta, isTrue);
    expect(delta.changed, unorderedEquals(<String>['a.txt', 'c.txt']));
    expect(delta.deleted, <String>['b.txt']);
    // 归档文件名不可读（哈希名），无 `<轮次>` 可读目录/文件，内容非明文。
    final String turnDir = '$projectDir${pathSep}checkpoints${pathSep}s1';
    expect(store.archiveFile('s1', 0).existsSync(), isTrue);
    expect(store.archiveFile('s1', 1).existsSync(), isTrue);
    final List<String> names = Directory(turnDir)
        .listSync()
        .map((FileSystemEntity e) => e.path.split(pathSep).last)
        .toList();
    // 无可读轮次名、无扩展名（看不出是 gzip）。
    expect(
      names.any(
        (String n) => n == '0' || n == '1' || n == '0.gz' || n == '1.gz',
      ),
      isFalse,
    );
    expect(names.any((String n) => n.endsWith('.gz')), isFalse);
    expect(names, contains('index'));
    final List<int> raw = store.archiveFile('s1', 1).readAsBytesSync();
    expect(utf8.decode(raw, allowMalformed: true).contains('v1'), isFalse);
    // list 有效文件数 = base(2) + changed新增(1) - deleted(1) = 2。
    expect(store.list('s1').last.files, 2);
  });

  test('mtime+size 不变的文件不进差量（不重复复制）', () async {
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore();
    writeWorkspace(root, 'a.txt', 'same');
    await store.snapshot('s1', 0);
    await store.snapshot('s1', 1);

    final CheckpointManifest delta = store.manifestOf('s1', 1);
    expect(delta.changed, isEmpty);
    expect(delta.deleted, isEmpty);
  });

  test('prune 保留 base + 最近 keep-1 个差量；keep<=0 不裁剪', () async {
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore(
      keep: 3,
    );
    writeWorkspace(root, 'a.txt', 'v0');
    await store.snapshot('s1', 0);
    for (int turn = 1; turn < 5; turn++) {
      writeWorkspace(root, 'a.txt', 'v$turn');
      await store.snapshot('s1', turn);
    }
    expect(store.turnsOf('s1'), <int>[0, 3, 4]);

    final (ArchiveCheckpointStore unlimited, _, _) = createArchiveStore(
      keep: 0,
    );
    await unlimited.snapshot('s2', 0);
    for (int turn = 1; turn < 4; turn++) {
      await unlimited.snapshot('s2', turn);
    }
    expect(unlimited.turnsOf('s2'), <int>[0, 1, 2, 3]);
  });

  test('缺失检查点 / 缺失清单抛 CheckpointException', () async {
    final (ArchiveCheckpointStore store, _, _) = createArchiveStore();
    expect(
      () => store.manifestOf('s1', 9),
      throwsA(isA<CheckpointException>()),
    );
    await store.snapshot('s1', 0);
    store.archiveFile('s1', 0).deleteSync();
    expect(
      () => store.manifestOf('s1', 0),
      throwsA(isA<CheckpointException>()),
    );
  });

  test('旧格式兼容：无 kind 的清单按 base 读（files 为字符串路径）', () {
    final (ArchiveCheckpointStore store, _, String projectDir) =
        createArchiveStore();
    final String legacy =
        '$projectDir${pathSep}checkpoints${pathSep}s1${pathSep}0';
    Directory(legacy).createSync(recursive: true);
    File(
      '$legacy${pathSep}manifest.json',
    ).writeAsStringSync('{"turn":0,"files":["a.txt","b.txt"]}');

    final CheckpointManifest manifest = store.manifestOf('s1', 0);
    expect(manifest.isDelta, isFalse);
    expect(
      manifest.files.map((CheckpointFileEntry e) => e.path),
      unorderedEquals(<String>['a.txt', 'b.txt']),
    );
  });

  test('符号链接跳过；空工作区 base 清单为空', () async {
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore();
    writeWorkspace(root, 'a.txt', 'x');
    final Link link = Link('$root${pathSep}link.txt');
    link.createSync('$root${pathSep}a.txt');

    await store.snapshot('s1', 0);

    final CheckpointManifest base = store.manifestOf('s1', 0);
    expect(base.files.map((CheckpointFileEntry e) => e.path), <String>[
      'a.txt',
    ]);

    final (ArchiveCheckpointStore emptyStore, _, _) = createArchiveStore();
    await emptyStore.snapshot('s2', 0);
    expect(emptyStore.manifestOf('s2', 0).files, isEmpty);
  });

  test('readFile 读 base 与差量内容；删除/缺失/只读路径返回 null', () async {
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore();
    writeWorkspace(root, 'a.txt', 'v0');
    writeWorkspace(root, 'b.txt', 'b0');
    await store.snapshot('s1', 0);

    writeWorkspace(root, 'a.txt', 'v1');
    writeWorkspace(root, 'c.txt', 'c1');
    File('$root${pathSep}b.txt').deleteSync();
    await store.snapshot('s1', 1);

    expect(utf8.decode((await store.readFile('s1', 0, 'a.txt'))!), 'v0');
    expect(utf8.decode((await store.readFile('s1', 1, 'a.txt'))!), 'v1');
    // 差量里没变的文件要回落到 base（diff 的两侧都得有内容）。
    expect(utf8.decode((await store.readFile('s1', 1, 'c.txt'))!), 'c1');
    // 该轮已删除 / 从未存在 / 轮次不存在：null。
    expect(await store.readFile('s1', 1, 'b.txt'), isNull);
    expect(await store.readFile('s1', 0, 'c.txt'), isNull);
    expect(await store.readFile('s1', 9, 'a.txt'), isNull);
    // 只读 / 越界路径一律 null（产品只读前缀由 policy 注入）。
    writeWorkspace(root, '.opencode/config.json', '{}');
    expect(await store.readFile('s1', 1, '.opencode/config.json'), isNull);
    expect(await store.readFile('s1', 1, '.OPENCODE/config.json'), isNull);
    expect(await store.readFile('s1', 1, '../outside.txt'), isNull);
  });
}
