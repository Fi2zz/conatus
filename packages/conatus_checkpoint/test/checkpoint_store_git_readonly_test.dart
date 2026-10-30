/// 影子 git 恢复的只读路径判定：策略声明的只读目录整体拒绝物化。
library;

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

import 'checkpoint_shadow_fixtures.dart';

void main() {
  test('恢复拒绝含 .opencode 的旧快照（fail-closed，一个文件都不动）', () async {
    if (!await const ProcessGitRunner().available()) return;
    final ShadowFixture f = createShadowFixture();
    f.write('a.txt', 'v0');
    await f.store.snapshot('s1', 0);

    // 模拟旧版本采集侧未排除 .opencode：手工提交进影子仓库并改索引指向它。
    f.write('.opencode/README.md', 'mine');
    f.shadowGit(<String>['add', '-f', '.opencode/README.md']);
    f.shadowGit(<String>['commit', '--quiet', '-m', 'legacy']);
    final String legacy = f.shadowGit(<String>['rev-parse', 'HEAD']).trim();
    f.pointIndexAt('s1', 0, legacy);

    f.write('a.txt', 'worktree-later');
    await expectLater(
      f.store.restore('s1', 0),
      throwsA(
        isA<CheckpointException>().having(
          (CheckpointException e) => e.code,
          'code',
          'read-only-path',
        ),
      ),
      reason: 'read-tree --reset -u 会把只读目录物化回工作区，必须整体拒绝',
    );
    expect(f.read('a.txt'), 'worktree-later', reason: '拒绝时一个文件都不该动');
    expect(f.read('.opencode/README.md'), 'mine');
  });
}
