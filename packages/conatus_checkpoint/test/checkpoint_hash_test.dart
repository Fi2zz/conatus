/// delta 哈希检测：mtime+size 相同但内容变 → 差量包含；旧条目保守处理。
library;

import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

(ArchiveCheckpointStore, String, String) _setup() {
  final Directory dir = Directory.systemTemp.createTempSync('conatus-cp-hash');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String root = dir.path;
  final String projectDir = '$root${Platform.pathSeparator}.conatus';
  Directory(projectDir).createSync();
  return (
    ArchiveCheckpointStore(root: root, projectDir: projectDir),
    root,
    projectDir,
  );
}

/// 整秒 mtime（macOS 的 setLastModifiedSync 只到秒级，用整秒可精确还原）。
final DateTime kWholeSecond = DateTime.fromMillisecondsSinceEpoch(
  1700000000000,
);

/// 写 [content] 并把 mtime 固定到 [kWholeSecond]（与 base 完全一致）。
void _writeFixedStat(String root, String rel, String content) {
  final File file = File('$root${Platform.pathSeparator}$rel');
  file.writeAsStringSync(content);
  file.setLastModifiedSync(kWholeSecond);
}

void main() {
  test('内容变但 mtime+size 一致 → 差量仍包含（哈希兜底）', () async {
    final (ArchiveCheckpointStore store, String root, _) = _setup();
    _writeFixedStat(root, 'a.txt', 'AAAA');
    await store.snapshot('s1', 0);
    // 哈希在旁挂文件里（清单头只留 stat，避免为算哈希多读一遍内容）。
    expect(
      readCheckpointHashes(store.archiveFile('s1', 0))!['a.txt'],
      isNotNull,
    );

    // 同 size 不同内容，mtime 固定在同一整秒。
    _writeFixedStat(root, 'a.txt', 'BBBB');
    await store.snapshot('s1', 1);

    final CheckpointManifest delta = store.manifestOf('s1', 1);
    expect(delta.changed, <String>['a.txt']);
  });

  test('mtime+size 一致且内容未变 → 不进差量（哈希校验通过）', () async {
    final (ArchiveCheckpointStore store, String root, _) = _setup();
    _writeFixedStat(root, 'a.txt', 'AAAA');
    await store.snapshot('s1', 0);

    // 内容未动：mtime 再钉一次同一整秒，mtime/size/hash 全等 → 不算变。
    _writeFixedStat(root, 'a.txt', 'AAAA');
    await store.snapshot('s1', 1);

    expect(store.manifestOf('s1', 1).changed, isEmpty);
  });

  test('旧清单（无 hash 条目）→ 保守按变化处理', () async {
    final (ArchiveCheckpointStore store, String root, String projectDir) =
        _setup();
    _writeFixedStat(root, 'a.txt', 'AAAA');
    await store.snapshot('s1', 0);
    // 用旧格式明文清单（files 为字符串路径、无 hash）替换新归档。
    store.archiveFile('s1', 0).deleteSync();
    final String legacy = '$projectDir${Platform.pathSeparator}checkpoints'
        '${Platform.pathSeparator}s1${Platform.pathSeparator}0';
    Directory(legacy).createSync(recursive: true);
    File(
      '$legacy${Platform.pathSeparator}manifest.json',
    ).writeAsStringSync('{"turn":0,"files":["a.txt"]}');

    _writeFixedStat(root, 'a.txt', 'BBBB');
    await store.snapshot('s1', 1);

    final CheckpointManifest delta = store.manifestOf('s1', 1);
    expect(delta.changed, <String>['a.txt']);
  });
}
