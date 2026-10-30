/// 解析**全局** gitignore（`core.excludesFile`）忽略了哪些路径，供快照排除。
///
/// ## 为什么只认全局、不认工作区的 `.gitignore`
///
/// 两者回答的是不同问题：
///
/// - 全局 gitignore 是**机器级**的 housekeeping：`.DS_Store`、`*.swp`、
///   `Thumbs.db`、编辑器临时文件。这些进快照毫无价值，纯占空间，且会让
///   每轮 diff 噪声更大。排除掉是净收益。
/// - 工作区 `.gitignore` 是**项目级**的「这些不进版本库」——`build/`、
///   `.dart_tool/`、`pubspec.lock`……「不进版本库」不等于「不该备份」。
///   对一个能回滚工作区文件的 agent 来说，构建产物恰恰是**最需要能被回滚**
///   的东西（构建脚本改了它们，误操作了它们）。故不采纳。
///
/// 忽略工作区 `.gitignore` 也是本实现吃过的教训：影子快照曾因此只收 293 个
/// 文件（swiftus 的 `.gitignore` 挡掉了 `.build/` 等），恢复按残缺清单把
/// 其余 9119 个全删了。
///
/// ## 怎么只问全局
///
/// `git check-ignore -v` 的输出是 `<来源>:<行号>:<模式>\t<路径>`，**来源可
/// 区分**：全局 excludesFile 是绝对路径，工作区 `.gitignore` 是相对路径、
/// `.git/info/exclude` 又是另一个位置。只留下来源等于 excludesFile 的那些行
/// 即可，无需自己解析 gitignore 语法（否定规则 `!`、目录限定 `/`、`**`
/// 等相当容易写错）。
library;

import 'dart:convert';
import 'dart:io';

import 'checkpoint_types.dart';
import 'shadow_git_runner.dart';

/// 全局 gitignore 忽略了 [candidates] 里的哪些路径（工作区相对路径）。
///
/// 未配置全局 excludesFile 时返回空集（等价于「没有额外排除」）。**解析失败
/// 抛 [CheckpointException]（`git-failed`）**，不返回残缺集：恢复会按这个集合
/// 决定删哪些「多余文件」，把失败当成「没有排除」就会误删用户的文件。
Future<Set<String>> resolveGlobalGitIgnore({
  required GitRunner git,
  required String gitDir,
  required String workTree,
  required List<String> candidates,
}) async {
  if (candidates.isEmpty) return const <String>{};
  final String? excludesFile = await _globalExcludesFile(
    git: git,
    gitDir: gitDir,
    workTree: workTree,
  );
  if (excludesFile == null) return const <String>{};
  // 配置文件不存在 = 没有任何全局规则（不是解析失败）。
  if (!File(excludesFile).existsSync()) return const <String>{};

  // check-ignore 一次只吃有限的 argv，分批以避上限。
  final Set<String> ignored = <String>{};
  for (int i = 0; i < candidates.length; i += _batch) {
    final int end =
        i + _batch > candidates.length ? candidates.length : i + _batch;
    final GitResult result = await git.run(
      <String>[
        'check-ignore',
        '--verbose',
        '--no-index',
        ...candidates.sublist(i, end),
      ],
      gitDir: gitDir,
      workTree: workTree,
    );
    // check-ignore 对「有忽略命中」返回 0、对「全部未命中」返回 1，两者都正常。
    if (result.exitCode != 0 && result.exitCode != 1) {
      throw CheckpointException(
        'git-failed',
        '解析全局 gitignore 失败：${_detail(result)}',
      );
    }
    for (final String line in const LineSplitter().convert(result.stdout)) {
      // check-ignore 的路径本身不会含换行，逐行拆安全。
      final int tab = line.indexOf('\t');
      if (tab <= 0) continue;
      final String source = line.substring(0, tab).split(':').first;
      if (source != excludesFile) continue; // 只认全局那一个来源
      final String path = line.substring(tab + 1);
      if (path.isNotEmpty) ignored.add(path);
    }
  }
  return ignored;
}

/// 全局 excludesFile 的绝对路径；未配置返回 `null`，读取失败抛错。
Future<String?> _globalExcludesFile({
  required GitRunner git,
  required String gitDir,
  required String workTree,
}) async {
  final GitResult result = await git.run(
    <String>['config', '--get', 'core.excludesFile'],
    gitDir: gitDir,
    workTree: workTree,
  );
  // 未配置时 git 返回 1；其余非 0 一律按读取失败处理。
  if (result.exitCode == 1) return null;
  if (!result.ok) {
    throw CheckpointException(
      'git-failed',
      '读取 core.excludesFile 失败：${_detail(result)}',
    );
  }
  final String path = result.stdout.trim();
  if (path.isEmpty) return null;
  return File(path).absolute.path;
}

/// 错误说明：stderr 优先，空则给退出码。
String _detail(GitResult result) {
  final String stderr = result.stderr.trim();
  return stderr.isEmpty ? '退出码 ${result.exitCode}' : stderr;
}

/// 单次 check-ignore 传多少路径。
const int _batch = 200;
