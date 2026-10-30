/// 影子 git 与全局 gitignore：排除集在快照与恢复两侧同源。
library;

import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

import 'checkpoint_shadow_fixtures.dart';
import 'checkpoint_shadow_runners.dart';

late bool _gitOk;

/// 带全局 ignore 的 store（新实例 = 新进程语义）。
GitShadowStore _ignoredStore(
  ShadowFixture f,
  File ignoreFile, {
  GitRunner? git,
}) =>
    GitShadowStore(
      root: f.root,
      projectDir: f.projectDir,
      git:
          git ?? GlobalIgnoresRunner(const ProcessGitRunner(), ignoreFile.path),
    );

/// `debug.log` 是否仍在工作区（全局忽略的文件必须活过恢复）。
bool _logSurvives(ShadowFixture f) => f.has('debug.log');

void main() {
  setUpAll(() async {
    _gitOk = await const ProcessGitRunner().available();
  });

  test('接管已有时间线后首次恢复：全局 gitignore 命中的文件不被当多余文件删掉', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    final File globalIgnore = globalIgnoreFile();
    final GitRunner runner = GlobalIgnoresRunner(
      const ProcessGitRunner(),
      globalIgnore.path,
    );

    // 带全局 ignore 拍基线：debug.log 被排除，不在快照里。
    final GitShadowStore writer = GitShadowStore(
      root: f.root,
      projectDir: f.projectDir,
      git: runner,
    );
    f.write('a.txt', 'v0');
    f.write('debug.log', 'noise');
    await writer.snapshot('s1', 0);

    // 模拟 `--session` 重开：新 store 实例（bind 接管、不拍快照）直接恢复。
    // 若恢复侧不重算全局 ignore，debug.log 会被当成「目标态没有的多余文件」
    // 删掉且不可恢复。
    final GitShadowStore resumed = GitShadowStore(
      root: f.root,
      projectDir: f.projectDir,
      git: runner,
    );
    f.write('a.txt', 'v1');
    await resumed.restore('s1', 0);

    expect(f.read('a.txt'), 'v0');
    expect(_logSurvives(f), isTrue, reason: '全局 gitignore 命中的文件不该被恢复删除');

    // 同一实例的第二次恢复：不能因为上一轮排除集被剪过就把文件丢掉。
    f.write('a.txt', 'v2');
    await resumed.restore('s1', 0);
    expect(f.read('a.txt'), 'v0');
    expect(_logSurvives(f), isTrue, reason: '第二次恢复不得抹掉排除集');
  });

  test('全局 gitignore：snapshot → restore 保住忽略文件', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    final GitShadowStore store = _ignoredStore(f, globalIgnoreFile());
    f.write('a.txt', 'v0');
    f.write('debug.log', 'noise');
    await store.snapshot('s1', 0);

    f.write('a.txt', 'v1');
    await store.restore('s1', 0);

    expect(f.read('a.txt'), 'v0');
    expect(_logSurvives(f), isTrue);
  });

  test('全局 gitignore：连续两轮快照不把忽略文件重新收进来', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    final GitShadowStore store = _ignoredStore(f, globalIgnoreFile());
    f.write('a.txt', 'v0');
    f.write('debug.log', 'noise');
    await store.snapshot('s1', 0);
    f.write('a.txt', 'v1');
    await store.snapshot('s1', 1);

    expect(
      await store.readFile('s1', 1, 'debug.log'),
      isNull,
      reason: '第二轮候选集不得被上一轮排除集剪枝，否则会重新收进忽略文件',
    );
    expect(
      f.lsTree(f.commitOf('s1', 1)),
      isNot(contains('debug.log')),
      reason: '忽略文件不该出现在第二轮提交树里',
    );
  });

  test('bind 接管后 recordTurn → restore 仍保住全局忽略文件', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    final File globalIgnore = globalIgnoreFile();
    final CheckpointManager manager = CheckpointManager(
      store: _ignoredStore(f, globalIgnore),
      options: const CheckpointOptions(),
    );
    f.write('a.txt', 'v0');
    f.write('debug.log', 'noise');
    await manager.bind('s1'); // turn 0
    f.write('a.txt', 'v1');
    await manager.recordTurn(); // turn 1
    manager.detach();

    // `--session` 重开：新实例 bind 接管（不拍快照），跑一轮后恢复上一轮。
    // 此时 store 的排除集刚被 recordTurn 算过；恢复侧若拿被它剪过的候选集
    // 重算，就会把排除清空并把 debug.log 当多余文件删掉。
    final CheckpointManager resumed = CheckpointManager(
      store: _ignoredStore(f, globalIgnore),
      options: const CheckpointOptions(),
    );
    await resumed.bind('s1'); // 接管 turn 1
    f.write('a.txt', 'v2');
    await resumed.recordTurn(); // turn 2

    final CheckpointRewindResult? back = await resumed.restoreTo('s1', 0);
    expect(back, isNotNull);
    expect(f.read('a.txt'), 'v0');
    expect(_logSurvives(f), isTrue);
  });

  test('全局 gitignore 解析失败：恢复中止，一个文件都不动', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    final File globalIgnore = globalIgnoreFile();
    final GitShadowStore writer = _ignoredStore(f, globalIgnore);
    f.write('a.txt', 'v0');
    await writer.snapshot('s1', 0);

    final GitShadowStore broken = _ignoredStore(
      f,
      globalIgnore,
      git: FailingCheckIgnoreRunner(
        const ProcessGitRunner(),
        globalIgnore.path,
      ),
    );
    f.write('a.txt', 'v1');

    await expectLater(
      broken.restore('s1', 0),
      throwsA(
        isA<CheckpointException>().having(
          (CheckpointException e) => e.code,
          'code',
          'git-failed',
        ),
      ),
      reason: '解析不出排除集时必须中止，不能带着更小的集合去删文件',
    );
    expect(f.read('a.txt'), 'v1', reason: '中止发生在改动任何文件之前');
  });
}
