/// 工作区的 git 差异（`/diff` 的 `working` 范围）：已跟踪改动 + 未跟踪文件。
///
/// 只读：只跑 `git diff` / `git ls-files` 与读文件。不在 git 仓库内返回
/// `null`（回落到轮次差异）；git 本身失败则返回空列表并在 [notice] 里说明。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_diff/conatus_diff.dart';

/// 单次最多读取多少个未跟踪文件的内容；其余只给文件级截断条目。
const int kMaxUntrackedFiles = 200;

/// 单个未跟踪文件的读取预算（字节）；超过只给文件级截断条目。
const int kMaxUntrackedBytes = 1024 * 1024;

/// git 子进程环境：只读采集不抢索引锁（`git diff` 会在某些仓库上顺带写
/// `index.lock`，与用户同时操作会互相阻塞）。
const Map<String, String> _gitEnvironment = <String, String>{
  'GIT_OPTIONAL_LOCKS': '0',
};

/// 工作区差异采集器。
class WorkingDiff {
  WorkingDiff(this.workdir, {this.acceptsPath});

  /// 工作区根（绝对路径）。
  final String workdir;

  /// 路径是否可见（复用检查点的排除面）；缺省全可见。
  final bool Function(String path)? acceptsPath;

  /// 最近一次失败说明（git 不可用 / 命令失败）；正常为 `null`。
  String? notice;

  /// 采集差异；不在 git 仓库内返回 `null`。
  Future<List<FileDiff>?> load() async {
    final _RepoProbe probe = await _probe();
    if (probe == _RepoProbe.notRepo) return null;
    if (probe == _RepoProbe.failed) return const <FileDiff>[];
    final ProcessResult result = await Process.run(
      'git',
      <String>[
        'diff',
        '--no-ext-diff',
        '--no-color',
        '--no-textconv',
        '--unified=3',
      ],
      workingDirectory: workdir,
      environment: _gitEnvironment,
    );
    if (result.exitCode != 0) {
      notice = 'git diff 失败：${result.stderr.toString().trim()}';
      return const <FileDiff>[];
    }
    final List<FileDiff> diffs = <FileDiff>[
      for (final FileDiff diff in parseUnifiedDiff(result.stdout.toString()))
        if (_visible(diff.path)) diff,
      ...await _untrackedDiffs(),
    ];
    diffs.sort((FileDiff a, FileDiff b) => a.path.compareTo(b.path));
    return diffs;
  }

  Future<_RepoProbe> _probe() async {
    try {
      final ProcessResult result = await Process.run(
        'git',
        <String>['rev-parse', '--is-inside-work-tree'],
        workingDirectory: workdir,
        environment: _gitEnvironment,
      );
      if (result.exitCode != 0) return _RepoProbe.notRepo;
      if (result.stdout.toString().trim() != 'true') {
        notice = 'git rev-parse 未返回工作区（裸仓库或受保护仓库）';
        return _RepoProbe.failed;
      }
      return _RepoProbe.repo;
    } on ProcessException catch (e) {
      notice = 'git 不可用：${e.message}';
      return _RepoProbe.failed;
    }
  }

  /// 未跟踪文件按新增处理（`--exclude-standard` 尊重 `.gitignore`）。
  Future<List<FileDiff>> _untrackedDiffs() async {
    final ProcessResult result = await Process.run(
      'git',
      <String>['ls-files', '--others', '--exclude-standard', '-z'],
      workingDirectory: workdir,
      environment: _gitEnvironment,
    );
    if (result.exitCode != 0) {
      notice = 'git ls-files 失败：${result.stderr.toString().trim()}';
      return const <FileDiff>[];
    }
    final List<String> paths = <String>[
      for (final String path in result.stdout.toString().split('\u0000'))
        if (path.isNotEmpty && _visible(path)) path,
    ];
    final List<FileDiff> diffs = <FileDiff>[];
    for (int index = 0; index < paths.length; index++) {
      final FileDiff? diff = index < kMaxUntrackedFiles
          ? await _untracked(paths[index])
          : _truncated(paths[index]);
      if (diff != null) diffs.add(diff);
    }
    return diffs;
  }

  Future<FileDiff?> _untracked(String path) async {
    final File file = File(_absolute(path));
    try {
      if (await file.length() > kMaxUntrackedBytes) return _truncated(path);
      final List<int> bytes = await file.readAsBytes();
      final List<FileDiff> diffs = diffLines(
        path,
        null,
        utf8.decode(bytes, allowMalformed: true),
      );
      return diffs.isEmpty ? null : diffs.single;
    } on FileSystemException {
      return null;
    }
  }

  FileDiff _truncated(String path) => FileDiff(
        path: path,
        status: 'added',
        hunks: const <DiffHunk>[],
        truncated: true,
      );

  bool _visible(String path) => acceptsPath?.call(path) ?? true;

  String _absolute(String rel) => '$workdir${Platform.pathSeparator}'
      '${rel.replaceAll('/', Platform.pathSeparator)}';
}

/// `rev-parse` 的三态：仓库 / 不是仓库 / git 本身失败。
enum _RepoProbe { repo, notRepo, failed }
