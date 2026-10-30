/// 影子 git 的按文件读取 / 两轮差异 / 暂存校验 / 对象复用。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

import 'checkpoint_shadow_fixtures.dart';
import 'checkpoint_shadow_runners.dart';

late bool _gitOk;

void main() {
  setUpAll(() async {
    _gitOk = await const ProcessGitRunner().available();
  });

  test('暂存不完整时报错而非静默产出残缺快照', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    f.write('a.txt', 'v0');
    f.write('b.txt', 'v0');
    // 让 `ls-files --cached` 少报一个路径 = 精确模拟「git 静默不收」。
    // 真实世界的原因就是嵌套版本库（`git add` 跳过且 rc=0 无告警）。
    final GitShadowStore store = GitShadowStore(
      root: f.root,
      projectDir: f.projectDir,
      git: const DroppingRunner(ProcessGitRunner(), 'b.txt'),
    );
    await expectLater(
      store.snapshot('s1', 0),
      throwsA(
        isA<CheckpointException>()
            .having(
              (CheckpointException e) => e.code,
              'code',
              'stage-incomplete',
            )
            .having(
              (CheckpointException e) => e.message,
              'message',
              contains('b.txt'),
            ),
      ),
      reason: '残缺快照会让恢复按残缺清单删文件，必须当场失败',
    );
  });

  test('跨会话复用对象：同内容不重存（只多出 tree+commit）', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    // 够大才能看出差别：重新存一份必然显著增长，复用则几乎不增长。
    f.write('big.bin', 'x' * 200000);
    await f.store.snapshot('s1', 0);
    final int afterFirst = f.objectStoreBytes();

    // 新会话、同样内容：blob 已存在，只该多出 tree + commit 两个小对象。
    await f.store.snapshot('s2', 0);
    final int growth = f.objectStoreBytes() - afterFirst;
    expect(
      growth,
      lessThan(20000),
      reason: '同内容应被复用；增长 $growth 字节说明又存了一份 200KB 内容',
    );
  });

  test('readFile 读该轮内容（含二进制）；缺失/只读路径返回 null', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    f.write('a.txt', 'v0');
    final List<int> blob = List<int>.generate(512, (int i) => (i * 37) & 0xff);
    File(f.path('blob.bin')).writeAsBytesSync(blob);
    await f.store.snapshot('s1', 0);

    f.write('a.txt', 'v1');
    File(f.path('blob.bin')).writeAsBytesSync(<int>[0xff, 0x00, 0x01]);
    await f.store.snapshot('s1', 1);

    expect(utf8.decode((await f.store.readFile('s1', 0, 'a.txt'))!), 'v0');
    expect(utf8.decode((await f.store.readFile('s1', 1, 'a.txt'))!), 'v1');
    expect(await f.store.readFile('s1', 0, 'blob.bin'), blob);
    expect(await f.store.readFile('s1', 1, 'missing.txt'), isNull);
    expect(await f.store.readFile('s1', 9, 'a.txt'), isNull);
    expect(await f.store.readFile('s1', 0, '.opencode/x'), isNull);
    expect(await f.store.readFile('s1', 0, '../outside.txt'), isNull);
  });

  test('changesBetween：added/modified/deleted/renamed', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    f.write('mod.txt', 'm0');
    f.write('del.txt', 'd0');
    f.write('old-name.txt', 'r0');
    await f.store.snapshot('s1', 0);

    f.write('mod.txt', 'm1');
    File(f.path('del.txt')).deleteSync();
    File(f.path('old-name.txt')).renameSync(f.path('new-name.txt'));
    f.write('add.txt', 'a1');
    await f.store.snapshot('s1', 1);

    final Map<String, String> forward = <String, String>{
      for (final CheckpointFileChange change in await f.store.changesBetween(
        's1',
        0,
        1,
      ))
        change.path: change.status,
    };
    expect(forward, <String, String>{
      'mod.txt': 'modified',
      'del.txt': 'deleted',
      'new-name.txt': 'renamed',
      'add.txt': 'added',
    });
    // 路径升序（与归档实现一致）。
    final List<String> ordered = <String>[
      for (final CheckpointFileChange change in await f.store.changesBetween(
        's1',
        0,
        1,
      ))
        change.path,
    ];
    expect(ordered, <String>['add.txt', 'del.txt', 'mod.txt', 'new-name.txt']);
    expect(await f.store.changesBetween('s1', 1, 1), isEmpty);
    final Map<String, String> backward = <String, String>{
      for (final CheckpointFileChange change in await f.store.changesBetween(
        's1',
        1,
        0,
      ))
        change.path: change.status,
    };
    expect(backward, <String, String>{
      'mod.txt': 'modified',
      'del.txt': 'added',
      'old-name.txt': 'renamed',
      'add.txt': 'deleted',
    });
  });
}
