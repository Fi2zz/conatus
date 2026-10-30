/// 归档后端的按轮差异读取：changesBetween 的过滤与缺失检查点语义。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

import 'checkpoint_fixtures.dart';

void main() {
  test('changesBetween：added/modified/deleted；同轮为空；反向对称', () async {
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore();
    writeWorkspace(root, 'mod.txt', 'm0');
    writeWorkspace(root, 'del.txt', 'd0');
    writeWorkspace(root, 'same.txt', 's0');
    await store.snapshot('s1', 0);

    writeWorkspace(root, 'mod.txt', 'm1');
    File('$root${pathSep}del.txt').deleteSync();
    writeWorkspace(root, 'add.txt', 'a1');
    await store.snapshot('s1', 1);

    final Map<String, String> forward = _summary(
      await store.changesBetween('s1', 0, 1),
    );
    expect(forward, <String, String>{
      'mod.txt': 'modified',
      'del.txt': 'deleted',
      'add.txt': 'added',
    });
    expect(await store.changesBetween('s1', 1, 1), isEmpty);
    expect(_summary(await store.changesBetween('s1', 1, 0)), <String, String>{
      'mod.txt': 'modified',
      'del.txt': 'added',
      'add.txt': 'deleted',
    });
  });

  test('changesBetween 跨多轮：只报真正变化的文件（内容比对兜底）', () async {
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore();
    writeWorkspace(root, 'mod.txt', 'm0');
    await store.snapshot('s1', 0);
    writeWorkspace(root, 'mod.txt', 'm1');
    writeWorkspace(root, 'add.txt', 'a1'); // 两轮之间不变
    await store.snapshot('s1', 1);
    writeWorkspace(root, 'mod.txt', 'm2');
    await store.snapshot('s1', 2);

    final Map<String, String> changes = _summary(
      await store.changesBetween('s1', 1, 2),
    );
    expect(
        changes,
        <String, String>{
          'mod.txt': 'modified',
        },
        reason: 'add.txt 在两轮里都相对 base 变化，但轮间内容相同，不算变化');
  });

  test('changesBetween / readFile 过滤只读路径（大小写不敏感）', () async {
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore();
    writeWorkspace(root, 'a.txt', 'v0');
    await store.snapshot('s1', 0);
    // 手工造一个含 .opencode 的旧归档：采集侧现在会排除它，故直接写归档；
    // 删掉索引让 list() 按归档头部重建。
    await writeCheckpointArchive(
      store.archiveFile('s1', 2),
      const CheckpointManifest(
        kind: 'delta',
        turn: 2,
        changed: <String>['a.txt', '.opencode/x', '.OPENCODE/y'],
      ),
      <CheckpointArchiveEntry>[
        ('a.txt', utf8.encode('v2')),
        ('.opencode/x', utf8.encode('x')),
        ('.OPENCODE/y', utf8.encode('y')),
      ],
    );
    store.indexFile('s1').deleteSync();

    final List<CheckpointFileChange> changes = await store.changesBetween(
      's1',
      0,
      2,
    );
    expect(changes.map((CheckpointFileChange c) => c.path), <String>['a.txt']);
    // 归档里**确实有**这两个条目，仍须一律读不到（不是「碰巧不存在」）。
    expect(await store.readFile('s1', 2, '.opencode/x'), isNull);
    expect(
      await store.readFile('s1', 2, '.OPENCODE/y'),
      isNull,
      reason: 'APFS / NTFS 上 .OPENCODE 就是 .opencode',
    );
  });

  test('changesBetween 轮次不存在抛 missing-checkpoint（与 git 后端同码）', () async {
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore();
    writeWorkspace(root, 'a.txt', 'v0');
    await store.snapshot('s1', 0);

    await expectLater(
      store.changesBetween('s1', 0, 7),
      throwsA(
        isA<CheckpointException>().having(
          (CheckpointException e) => e.code,
          'code',
          'missing-checkpoint',
        ),
      ),
    );
  });

  test('turn 的归档缺失：readFile 返回 null，changesBetween 报错', () async {
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore();
    writeWorkspace(root, 'a.txt', 'v0');
    await store.snapshot('s1', 0);
    writeWorkspace(root, 'a.txt', 'v1');
    await store.snapshot('s1', 1);
    // 索引还记着 turn 1，但归档被删（磁盘损坏 / 手工清理）。
    store.archiveFile('s1', 1).deleteSync();

    expect(await store.readFile('s1', 1, 'a.txt'), isNull);
    await expectLater(
      store.changesBetween('s1', 0, 1),
      throwsA(
        isA<CheckpointException>().having(
          (CheckpointException e) => e.code,
          'code',
          'missing-checkpoint',
        ),
      ),
      reason: '不能退回 base 内容把「差量丢了」伪装成「文件没变」',
    );
  });
}

/// `path → status` 摘要（断言用）。
Map<String, String> _summary(
  List<CheckpointFileChange> changes,
) =>
    <String, String>{
      for (final CheckpointFileChange change in changes)
        change.path: change.status,
    };
