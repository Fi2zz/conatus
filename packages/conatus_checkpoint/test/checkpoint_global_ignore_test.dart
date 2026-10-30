/// 全局 gitignore 排除：只认全局 excludesFile，不认工作区 .gitignore。
///
/// 这些用例跑真实 git；无 git 环境下跳过。
library;

import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

import 'checkpoint_fixtures.dart';
import 'checkpoint_shadow_runners.dart';

late bool _gitOk;

void _write(String root, String rel, String content) {
  final File file = File('$root$pathSep$rel');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

/// 建临时工作区 + 影子 git dir（不初始化仓库，由用例决定）。
(Directory, String, String) _workspace() {
  final Directory ws = Directory.systemTemp.createTempSync('conatus-gg');
  addTearDown(() => ws.deleteSync(recursive: true));
  final String root = ws.path;
  final Directory proj = Directory('$root$pathSep.conatus')..createSync();
  final String gitDir = '${proj.path}${pathSep}checkpoints${pathSep}shadow.git';
  Directory(gitDir).parent.createSync(recursive: true);
  return (ws, root, gitDir);
}

void main() {
  setUpAll(() async {
    _gitOk = await const ProcessGitRunner().available();
  });

  Future<Set<String>> resolve(
    String root,
    String gitDir,
    List<String> candidates,
  ) async {
    const ProcessGitRunner base = ProcessGitRunner();
    await base.run(
      <String>['init', '--quiet'],
      gitDir: gitDir,
      workTree: root,
    );
    final File globalIgnore = globalIgnoreFile(
      contents: '*.log\n.DS_Store\nsecret-*\n',
    );
    return resolveGlobalGitIgnore(
      git: GlobalIgnoresRunner(base, globalIgnore.path),
      gitDir: gitDir,
      workTree: root,
      candidates: candidates,
    );
  }

  test('只采纳全局 excludesFile 的忽略，剔除工作区 .gitignore 的', () async {
    if (!_gitOk) return;
    final (_, String root, String gitDir) = _workspace();
    _write(root, '.gitignore', 'project-only.txt\nbuild/\n');
    _write(root, 'project-only.txt', 'x');
    _write(root, 'debug.log', 'x');
    _write(root, '.DS_Store', 'x');
    _write(root, 'secret-key.txt', 'x');
    _write(root, 'keep.dart', 'x');

    final Set<String> ignored = await resolve(root, gitDir, <String>[
      'project-only.txt',
      'debug.log',
      '.DS_Store',
      'secret-key.txt',
      'keep.dart',
    ]);

    expect(
      ignored,
      containsAll(<String>['debug.log', '.DS_Store', 'secret-key.txt']),
      reason: '全局 ignore 命中的应被排除',
    );
    expect(ignored, isNot(contains('keep.dart')), reason: '两边都不命中');
    expect(
      ignored,
      isNot(contains('project-only.txt')),
      reason: '只有工作区 .gitignore 命中——「不进版本库」不等于「不该备份」',
    );
  });

  test('未配置全局 excludesFile 时返回空集（保守降级）', () async {
    if (!_gitOk) return;
    final (_, String root, String gitDir) = _workspace();
    const ProcessGitRunner base = ProcessGitRunner();
    await base.run(
      <String>['init', '--quiet'],
      gitDir: gitDir,
      workTree: root,
    );
    final Set<String> ignored = await resolveGlobalGitIgnore(
      // 指向一个不存在的文件 = 等价于未配置
      git: const GlobalIgnoresRunner(
        ProcessGitRunner(),
        '/nonexistent/ignore',
      ),
      gitDir: gitDir,
      workTree: root,
      candidates: <String>['a.txt', 'b.txt'],
    );
    expect(ignored, isEmpty, reason: '解析不出就退回 conatus 自己的规则');
  });

  test('候选集为空时不问 git', () async {
    final (_, String root, String gitDir) = _workspace();
    final Set<String> ignored = await resolveGlobalGitIgnore(
      git: const UnavailableGitRunner(),
      gitDir: gitDir,
      workTree: root,
      candidates: const <String>[],
    );
    expect(ignored, isEmpty);
  });

  test('check-ignore 失败抛 git-failed 而非返回残缺集', () async {
    if (!_gitOk) return;
    final (_, String root, String gitDir) = _workspace();
    const ProcessGitRunner base = ProcessGitRunner();
    await base.run(
      <String>['init', '--quiet'],
      gitDir: gitDir,
      workTree: root,
    );
    _write(root, 'debug.log', 'x');
    final File globalIgnore = globalIgnoreFile();
    await expectLater(
      resolveGlobalGitIgnore(
        git: FailingCheckIgnoreRunner(base, globalIgnore.path),
        gitDir: gitDir,
        workTree: root,
        candidates: <String>['debug.log'],
      ),
      throwsA(
        isA<CheckpointException>().having(
          (CheckpointException e) => e.code,
          'code',
          'git-failed',
        ),
      ),
      reason: '把失败当成「没有排除」会让恢复误删用户的文件',
    );
  });
}
