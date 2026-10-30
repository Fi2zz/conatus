/// 影子 git 测试用的执行器替身：全局 gitignore 配置、失败注入、暂存丢路径。
library;

import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

/// 给执行器套一个固定的 `core.excludesFile`，模拟用户的全局 git 配置。
class GlobalIgnoresRunner implements GitRunner {
  const GlobalIgnoresRunner(this.inner, this.excludesFile);

  final GitRunner inner;
  final String excludesFile;

  List<String> _wrap(List<String> args) => <String>[
        '-c',
        'core.excludesFile=$excludesFile',
        ...args,
      ];

  @override
  Future<bool> available() => inner.available();

  @override
  Future<GitResult> run(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) =>
      inner.run(_wrap(args), gitDir: gitDir, workTree: workTree);

  @override
  GitResult runSync(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) =>
      inner.runSync(_wrap(args), gitDir: gitDir, workTree: workTree);
}

/// `check-ignore` 固定失败的执行器（config 仍可读）：验证解析失败 fail-closed。
class FailingCheckIgnoreRunner implements GitRunner {
  const FailingCheckIgnoreRunner(this.inner, this.excludesFile);

  final GitRunner inner;
  final String excludesFile;

  List<String> _wrap(List<String> args) => <String>[
        '-c',
        'core.excludesFile=$excludesFile',
        ...args,
      ];

  @override
  Future<bool> available() => inner.available();

  @override
  Future<GitResult> run(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) {
    if (args.contains('check-ignore')) {
      return Future<GitResult>.value(
        const GitResult(128, '', 'fatal: 模拟 check-ignore 失败'),
      );
    }
    return inner.run(_wrap(args), gitDir: gitDir, workTree: workTree);
  }

  @override
  GitResult runSync(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) =>
      inner.runSync(_wrap(args), gitDir: gitDir, workTree: workTree);
}

/// 包一层真实执行器，让 `ls-files --cached` 少报某个路径——用来验证
/// 「暂存不完整」时 store 会报错而不是静默产出残缺快照。
class DroppingRunner implements GitRunner {
  const DroppingRunner(this.inner, this.drop);

  final GitRunner inner;
  final String drop;

  @override
  Future<bool> available() => inner.available();

  @override
  Future<GitResult> run(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) async {
    final GitResult r = await inner.run(
      args,
      gitDir: gitDir,
      workTree: workTree,
    );
    return _maybeDrop(args, r);
  }

  @override
  GitResult runSync(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) =>
      _maybeDrop(args, inner.runSync(args, gitDir: gitDir, workTree: workTree));

  GitResult _maybeDrop(List<String> args, GitResult r) {
    if (!args.contains('ls-files')) return r;
    final List<String> kept = <String>[
      for (final String p in r.stdout.split('\u0000'))
        if (p.isNotEmpty && p != drop) p,
    ];
    return GitResult(r.exitCode, '${kept.join('\u0000')}\u0000', r.stderr);
  }
}

/// 固定内容的全局忽略配置文件（每个用例一份临时 home）。
File globalIgnoreFile({String contents = '*.log\n'}) {
  final Directory home =
      Directory.systemTemp.createTempSync('conatus-shadow-home');
  addTearDown(() => home.deleteSync(recursive: true));
  return File('${home.path}${Platform.pathSeparator}ignore')
    ..writeAsStringSync(contents);
}
