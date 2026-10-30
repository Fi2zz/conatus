/// delta 恢复：base 铺底 + 差量覆盖/删除 + 删当前多余（两步合成）。
library;

import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

(ArchiveCheckpointStore, String, String) _setup({int keep = 5}) {
  final Directory dir =
      Directory.systemTemp.createTempSync('conatus-cp-restore');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String root = dir.path;
  final String projectDir = '$root${Platform.pathSeparator}.conatus';
  Directory(projectDir).createSync();
  return (
    ArchiveCheckpointStore(root: root, projectDir: projectDir, keep: keep),
    root,
    projectDir,
  );
}

void _write(String root, String rel, String content) {
  final File file = File('$root${Platform.pathSeparator}$rel');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

String _read(String root, String rel) =>
    File('$root${Platform.pathSeparator}$rel').readAsStringSync();

bool _exists(String root, String rel) =>
    File('$root${Platform.pathSeparator}$rel').existsSync();

/// 典型场景：base(a,b) → turn1 改 a 删 b 加 c → turn2 改 a。
Future<void> _scenario(String root, ArchiveCheckpointStore store) async {
  _write(root, 'a.txt', 'a0');
  _write(root, 'b.txt', 'b0');
  await store.snapshot('s1', 0);
  _write(root, 'a.txt', 'a1');
  File('$root${Platform.pathSeparator}b.txt').deleteSync();
  _write(root, 'c.txt', 'c1');
  await store.snapshot('s1', 1);
  _write(root, 'a.txt', 'a2');
  await store.snapshot('s1', 2);
}

void main() {
  test('恢复 base：全量铺底 + 删当前多余', () async {
    final (ArchiveCheckpointStore store, String root, _) = _setup();
    await _scenario(root, store);
    // 把工作区改乱。
    _write(root, 'a.txt', '乱改');
    _write(root, 'x.txt', '多余');

    final CheckpointRestore result = await store.restore('s1', 0);

    expect(result.restored, 2); // a.txt + b.txt 铺底
    expect(result.deleted, 2); // c.txt + x.txt 删除（base 后创建的都删）
    expect(_read(root, 'a.txt'), 'a0');
    expect(_read(root, 'b.txt'), 'b0');
    expect(_exists(root, 'c.txt'), isFalse);
    expect(_exists(root, 'x.txt'), isFalse);
  });

  test('恢复差量：base 铺底 + changed 覆盖 + deleted 删除 + 删多余', () async {
    final (ArchiveCheckpointStore store, String root, _) = _setup();
    await _scenario(root, store);
    // 改乱：a 被改、b 被加回、c 被删、x 多余。
    _write(root, 'a.txt', '乱改');
    _write(root, 'b.txt', '乱加回');
    File('$root${Platform.pathSeparator}c.txt').deleteSync();
    _write(root, 'x.txt', '多余');

    final CheckpointRestore result = await store.restore('s1', 1);

    expect(result.restored, 3); // base a + changed a,c
    expect(result.deleted, 2); // b（目标态删除）+ x（多余）
    expect(_read(root, 'a.txt'), 'a1');
    expect(_exists(root, 'b.txt'), isFalse); // deleted 目标态
    expect(_read(root, 'c.txt'), 'c1');
    expect(_exists(root, 'x.txt'), isFalse);
  });

  test('恢复到最新差量得到最新状态', () async {
    final (ArchiveCheckpointStore store, String root, _) = _setup();
    await _scenario(root, store);

    final CheckpointRestore result = await store.restore('s1', 2);

    expect(_read(root, 'a.txt'), 'a2');
    expect(_exists(root, 'b.txt'), isFalse);
    expect(_read(root, 'c.txt'), 'c1');
    expect(result.restored, 3);
  });

  test('恢复不触碰排除项（.conatus / .git）', () async {
    final (ArchiveCheckpointStore store, String root, String projectDir) =
        _setup();
    _write(root, 'a.txt', 'v0');
    _write(root, '.git/config', 'git-state');
    await store.snapshot('s1', 0);

    _write(root, 'a.txt', 'v1');
    _write(root, '.git/config', 'new-git');
    _write(root, '.conatus/new.json', 'data');
    await store.restore('s1', 0);

    expect(_read(root, 'a.txt'), 'v0');
    expect(_read(root, '.git/config'), 'new-git');
    expect(_read(root, '.conatus/new.json'), 'data');
  });

  test('缺失检查点抛 CheckpointException', () async {
    final (ArchiveCheckpointStore store, _, _) = _setup();
    await expectLater(
      store.restore('s1', 9),
      throwsA(isA<CheckpointException>()),
    );
  });
}
