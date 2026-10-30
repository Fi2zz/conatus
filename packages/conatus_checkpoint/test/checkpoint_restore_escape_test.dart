/// checkpoint 恢复侧符号链接防护：文件链接不穿透、父目录链接 fail-closed。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

import 'checkpoint_fixtures.dart';

/// 造一个归档（清单 + 条目），用于模拟旧版本产生的检查点。
Future<void> _writeArchive(
  File target,
  CheckpointManifest manifest,
  Map<String, String> files,
) async {
  final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
    target,
    manifest,
  );
  for (final MapEntry<String, String> entry in files.entries) {
    writer.addBytes(entry.key, utf8.encode(entry.value));
  }
  await writer.close();
}

void main() {
  test('rewind 不穿透文件符号链接覆写工作区外文件', () async {
    if (Platform.isWindows) return; // symlink 需权限
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore(
      workspace: 'ws',
    );
    final Directory outside = Directory.systemTemp.createTempSync(
      'conatus-cp-ext',
    );
    addTearDown(() => outside.deleteSync(recursive: true));
    final String external = '${outside.path}${pathSep}external.txt';
    File(external).writeAsStringSync('外部原文');

    writeWorkspace(root, 'a.txt', 'v0');
    await store.snapshot('s', 0);
    File('$root${pathSep}a.txt').deleteSync();
    Link('$root${pathSep}a.txt').createSync(external);

    await store.restore('s', 0);

    expect(File(external).readAsStringSync(), '外部原文');
    final String restored = '$root${pathSep}a.txt';
    expect(
      FileSystemEntity.typeSync(restored, followLinks: false),
      FileSystemEntityType.file,
    );
    expect(File(restored).readAsStringSync(), 'v0');
  });

  test('rewind 父目录为外部 symlink 时 fail-closed 且工作区不动', () async {
    if (Platform.isWindows) return;
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore(
      workspace: 'ws',
    );
    final Directory outside = Directory.systemTemp.createTempSync(
      'conatus-cp-ext',
    );
    addTearDown(() => outside.deleteSync(recursive: true));
    writeWorkspace(outside.path, 'b.txt', '外部原文');

    writeWorkspace(root, 'sub/b.txt', 'v0');
    await store.snapshot('s', 0);
    Directory('$root${pathSep}sub').deleteSync(recursive: true);
    Link('$root${pathSep}sub').createSync(outside.path);

    await expectLater(
      store.restore('s', 0),
      throwsA(
        isA<CheckpointException>().having(
          (CheckpointException e) => e.code,
          'code',
          'restore-escape',
        ),
      ),
    );
    expect(
      File('${outside.path}${pathSep}b.txt').readAsStringSync(),
      '外部原文',
    );
  });

  test('restore base 不写回清单里的 .opencode（只读约束）', () async {
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore(
      workspace: 'ws',
    );
    await _writeArchive(
      store.archiveFile('s', 0),
      const CheckpointManifest(
        kind: 'base',
        turn: 0,
        files: <CheckpointFileEntry>[
          CheckpointFileEntry(path: 'a.txt', mtimeMs: 1, size: 2),
          CheckpointFileEntry(
            path: '.opencode/commands/x.md',
            mtimeMs: 1,
            size: 5,
          ),
        ],
      ),
      <String, String>{'a.txt': 'v0', '.opencode/commands/x.md': 'pwned'},
    );

    final CheckpointRestore result =
        await restoreArchiveCheckpoint(store, 's', 0);

    expect(result.restored, 1);
    expect(readWorkspace(root, 'a.txt'), 'v0');
    expect(Directory('$root$pathSep.opencode').existsSync(), isFalse);
  });

  test('restore delta 不写回也不删除 .opencode 下文件', () async {
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore(
      workspace: 'ws',
    );
    writeWorkspace(root, '.opencode/keep.md', 'mine');
    await _writeArchive(
      store.archiveFile('s', 0),
      const CheckpointManifest(
        kind: 'base',
        turn: 0,
        files: <CheckpointFileEntry>[
          CheckpointFileEntry(path: 'a.txt', mtimeMs: 1, size: 2),
        ],
      ),
      <String, String>{'a.txt': 'v0'},
    );
    await _writeArchive(
      store.archiveFile('s', 1),
      const CheckpointManifest(
        kind: 'delta',
        turn: 1,
        changed: <String>['b.txt', '.opencode/evil.md'],
        deleted: <String>['.opencode/keep.md'],
      ),
      <String, String>{'b.txt': 'v1', '.opencode/evil.md': 'pwned'},
    );

    final CheckpointRestore result =
        await restoreArchiveCheckpoint(store, 's', 1);

    expect(result.restored, 2);
    expect(readWorkspace(root, 'b.txt'), 'v1');
    expect(readWorkspace(root, '.opencode/keep.md'), 'mine');
    expect(workspaceHas(root, '.opencode/evil.md'), isFalse);
  });
}
