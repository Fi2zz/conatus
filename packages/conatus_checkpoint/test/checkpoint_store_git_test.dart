/// 影子 git 仓库存储：基线/差量快照、恢复（含 rsync 删除）、不碰用户仓库。
///
/// 这些用例直接跑真实 git（影子方案的全部价值与全部风险都在 git 的行为上，
/// 塞 fake 等于把要测的东西测没了）。无 git 环境下整组跳过。
library;

import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

import 'checkpoint_shadow_fixtures.dart';

late bool _gitOk;

void main() {
  setUpAll(() async {
    _gitOk = await const ProcessGitRunner().available();
  });

  test('快照与恢复：改坏的文件回到基线状态', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    f.write('a.txt', 'v0');
    await f.store.snapshot('s1', 0, lastEventId: 'ev-0');

    f.write('a.txt', 'v1-broken');
    await f.store.snapshot('s1', 1);

    await f.store.restore('s1', 0);
    expect(f.read('a.txt'), 'v0');
  });

  test('rsync 语义：恢复会删掉该轮之后新增的文件', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    f.write('a.txt', 'v0');
    await f.store.snapshot('s1', 0);

    f.write('b.txt', 'new');
    await f.store.snapshot('s1', 1);
    expect(f.read('b.txt'), 'new');

    await f.store.restore('s1', 0);
    expect(f.read('a.txt'), 'v0');
    expect(
      f.has('b.txt'),
      isFalse,
      reason: '目标态没有的文件必须被删（read-tree --reset -u，不是 checkout）',
    );
  });

  test('恢复会补回该轮之后被删的文件', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    f.write('a.txt', 'v0');
    f.write('b.txt', 'keep');
    await f.store.snapshot('s1', 0);

    File(f.path('b.txt')).deleteSync();
    await f.store.snapshot('s1', 1);

    await f.store.restore('s1', 0);
    expect(f.read('b.txt'), 'keep');
  });

  test('二进制文件不炸（sha256 / zlib 都按字节处理）', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    File(
      f.path('blob.bin'),
    ).writeAsBytesSync(List<int>.generate(200000, (int i) => (i * 31) & 0xff));
    await f.store.snapshot('s1', 0);
    File(f.path('blob.bin')).writeAsBytesSync(<int>[0xff, 0xfe, 0x00]);
    await f.store.snapshot('s1', 1);

    await f.store.restore('s1', 0);
    expect(File(f.path('blob.bin')).readAsBytesSync().length, 200000);
  });

  test('不污染用户仓库：log 不变、status 只多 untracked', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    f.write('a.txt', 'v0');
    Process.runSync('git', <String>[
      '-C',
      f.root,
      '-c',
      'user.email=a@b',
      '-c',
      'user.name=n',
      'add',
      '-A',
    ]);
    Process.runSync('git', <String>[
      '-C',
      f.root,
      '-c',
      'user.email=a@b',
      '-c',
      'user.name=n',
      'commit',
      '--quiet',
      '-m',
      'user commit',
    ]);
    final String before = Process.runSync('git', <String>[
      '-C',
      f.root,
      'log',
      '--oneline',
    ]).stdout as String;

    await f.store.snapshot('s1', 0);
    f.write('a.txt', 'v1');
    await f.store.snapshot('s1', 1);

    final String after = Process.runSync('git', <String>[
      '-C',
      f.root,
      'log',
      '--oneline',
    ]).stdout as String;
    expect(after, before, reason: '影子提交不得进用户仓库的历史');
  });
}
