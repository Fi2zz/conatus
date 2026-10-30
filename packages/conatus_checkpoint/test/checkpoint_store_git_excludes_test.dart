/// 影子 git 仓库的排除面：内置默认项、策略、嵌套仓库与工作区 .gitignore。
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

  test('排除项不进快照：.git / projectDir / build / 用户 ignore', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture(
      policy: shadowPolicy(ignore: <String>['secret']),
    );
    f.write('lib/main.dart', 'ok');
    f.write('build/out.bin', 'artifact');
    f.write('secret/key.txt', 'shh');
    f.write('.conatus/local.state', 's');
    await f.store.snapshot('s1', 0);

    final CheckpointRestore back = await f.store.restore('s1', 0);
    expect(back.restored, greaterThan(0));
    expect(
      f.has('build/out.bin'),
      isTrue,
      reason: 'build/ 被排除，不该在恢复时被当成多余文件删掉',
    );
    expect(f.has('secret/key.txt'), isTrue);
  });

  test('工作区的 .gitignore 不缩小快照（排除面只认 conatus 自己的规则）', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    // 回归用例：影子实现曾用 `git add --all`，git 顺从工作区的 .gitignore，
    // 快照只剩被 ignore 之外的少数文件；恢复按残缺清单的 rsync 语义把其余
    // 全删了（swiftus 上实测 9661 → 293，删掉 9119）。
    f.write('.gitignore', '.build/\nsecret/\n*.log\n');
    f.write('.build/out.bin', 'ARTIFACT');
    f.write('secret/k.txt', 'SHH');
    f.write('debug.log', 'LOG');
    f.write('keep.txt', 'KEEP');

    await f.store.snapshot('s1', 0);
    final Set<String> tracked = f.lsTree(f.commitOf('s1', 0)).toSet();
    expect(
      tracked,
      containsAll(<String>[
        '.build/out.bin', // 被工作区 .gitignore 排除，但对 conatus 要入快照
        'secret/k.txt',
        'debug.log',
        'keep.txt',
      ]),
      reason: '.gitignore 不该影响 conatus 的排除判定',
    );
  });

  test('conatus 自己的排除仍然生效（build/ 与 projectDir 不入快照）', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    f.write('lib/main.dart', 'ok');
    f.write('build/out.bin', 'artifact');
    f.write('.conatus/local.state', 's');
    await f.store.snapshot('s1', 0);

    final Set<String> tracked = f.lsTree(f.commitOf('s1', 0)).toSet();
    expect(tracked, contains('lib/main.dart'));
    expect(tracked, isNot(contains('build/out.bin')));
    expect(
      tracked.any((String p) => p.startsWith('.conatus/')),
      isFalse,
      reason: '影子仓库自身在 .conatus 下，绝不能被卷进快照',
    );
  });

  test('本轮被删的文件会在下一轮记录为删除', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    f.write('a.txt', 'v0');
    f.write('b.txt', 'gone-next-turn');
    await f.store.snapshot('s1', 0);

    File(f.path('b.txt')).deleteSync();
    await f.store.snapshot('s1', 1);

    final Set<String> at1 = f.lsTree(f.commitOf('s1', 1)).toSet();
    expect(at1, contains('a.txt'));
    expect(at1, isNot(contains('b.txt')), reason: '删除必须被记录');
  });

  test('嵌套 git 仓库整树排除：既不收也不会被恢复删掉', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    // `git worktree` / vendor 目录必中。git add 对落在嵌套仓库里的显式路径
    // 会**静默跳过**（rc=0、无告警），所以若不整树排除，快照会残缺而恢复
    // 会把整个子树删掉。
    final String inner = f.path('.worktrees/feature');
    Directory(inner).createSync(recursive: true);
    Process.runSync('git', <String>['init', '--quiet', inner]);
    f.write('.worktrees/feature/code.dart', 'INNER');
    f.write('top.dart', 'TOP');

    await f.store.snapshot('s1', 0);
    final Set<String> tracked = f.lsTree(f.commitOf('s1', 0)).toSet();
    expect(tracked, contains('top.dart'));
    expect(
      tracked.any((String p) => p.startsWith('.worktrees/')),
      isFalse,
      reason: '嵌套仓库的内部文件不该进快照（git 收不了，收了也不一致）',
    );

    // 关键：恢复时不能把它当「多余文件」删掉。
    await f.store.restore('s1', 0);
    expect(
      File('$inner${Platform.pathSeparator}code.dart').existsSync(),
      isTrue,
      reason: '排除项在恢复侧也要跳过，否则会被 rsync 删除',
    );
  });
}
