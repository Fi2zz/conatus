/// 影子 git 仓库的 git 执行缝：把「跑一条 git 命令」抽象成接口。
///
/// 与 `tools/git_tools.dart` 的 `runGit` 是两回事：那边是**工具**用的自由函
/// 数（拼字符串、走 `shell` 接缝、受命令策略约束，参数由模型拼），这边是
/// **基础设施**用的接口（argv 数组、直接 `Process.run`、不经命令策略）。
///
/// 为什么不经 `shell` 接缝：影子仓库的 git dir 位于工作区之外
/// （`<projectDir>/checkpoints/`），而命令策略与沙箱按工作区路径判定读写
/// 边界，git 自己去动那个目录会被拦。同时检查点快照是应用自身的可信行为，
/// 与快照/恢复直连 `dart:io` 同一信任域（见 checkpoint 设计 spec）。
///
/// 抽成接口的另一个理由是可测：git 不可用时（无二进制、精简容器）要有
/// 确定的降级路径，测试也需要能塞进 fake。
library;

import 'dart:io';

import 'git_process_output.dart';

/// 一条 git 命令的执行结果。
class GitResult {
  const GitResult(this.exitCode, this.stdout, this.stderr, {this.stdoutBytes});

  /// 进程退出码。
  final int exitCode;

  /// 标准输出（已按 UTF-8 解码，非法字节替换）。
  final String stdout;

  /// 标准错误。
  final String stderr;

  /// 标准输出的**原始字节**（`git show` 读二进制内容用）。
  ///
  /// [stdout] 会把非法 UTF-8 替换成 U+FFFD，二进制文件经它读出来就毁了；
  /// 需要字节级内容时读这个。测试里的假执行器可能不填（为 `null`）。
  final List<int>? stdoutBytes;

  /// 是否成功。
  bool get ok => exitCode == 0;
}

/// 影子仓库的 git 执行器。
abstract class GitRunner {
  /// 在 [gitDir] 为仓库、[workTree] 为工作区的上下文里跑 `git <args>`。
  ///
  /// [args] 是 argv 数组（不经 shell 解析，故无需引号转义）。
  Future<GitResult> run(
    List<String> args, {
    required String gitDir,
    required String workTree,
  });

  /// 同步版（`CheckpointStore.list` / `prune` 这类同步接口用）。
  ///
  /// 会阻塞事件循环，故只许用于低频路径（列表展示、裁剪），不得放进快照
  /// 或恢复的热路径。
  GitResult runSync(
    List<String> args, {
    required String gitDir,
    required String workTree,
  });

  /// 环境里是否有可用的 git。不可用时调用方应降级，不得抛异常。
  Future<bool> available();
}

/// 真实实现：直接 `Process.run('git', ...)`。
///
/// 每次调用独立进程，不复用——影子仓库的操作是低频的（每轮一次快照、
/// `/rewind` 时几次），复用 daemon 的复杂度不划算。身份与提交时间也用
/// `-c` 固定，避免依赖宿主的 git 全局配置（否则用户配了 `commit.gpgsign`
/// 或 hooks 会让快照失败）。
class ProcessGitRunner implements GitRunner {
  const ProcessGitRunner({this.defaultTimeout = const Duration(minutes: 5)});

  /// 单条命令的默认超时。
  final Duration defaultTimeout;

  @override
  Future<bool> available() async {
    try {
      final ProcessResult result = await Process.run('git', <String>[
        '--version',
      ]).timeout(const Duration(seconds: 5));
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<GitResult> run(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) async {
    final ProcessResult result = await Process.run(
      'git',
      <String>[
        '--git-dir=$gitDir',
        '--work-tree=$workTree',
        // 身份固定：宿主的 user.name/user.email 缺失不该让快照失败。
        '-c', 'user.email=conatus@localhost',
        '-c', 'user.name=conatus',
        // 不跑宿主配置的 hook / 签名：快照必须无外部依赖地成功。
        '-c', 'commit.gpgsign=false',
        '-c', 'core.hooksPath=/dev/null',
        '-c', 'gc.auto=0',
        '-c', 'advice.detachedHead=false',
        ...args,
      ],
      workingDirectory: workTree,
      stdoutEncoding: null,
    ).timeout(defaultTimeout);
    return GitResult(
      result.exitCode,
      gitOutputText(result.stdout),
      gitOutputText(result.stderr),
      stdoutBytes: gitOutputBytes(result.stdout),
    );
  }

  /// 同步版（[CheckpointStore.list] 等同步接口用；git 子进程会阻塞事件循环，
  /// 故只在低频路径上用）。
  @override
  GitResult runSync(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) {
    final ProcessResult result = Process.runSync(
      'git',
      <String>[
        '--git-dir=$gitDir',
        '--work-tree=$workTree',
        '-c',
        'user.email=conatus@localhost',
        '-c',
        'user.name=conatus',
        '-c',
        'commit.gpgsign=false',
        '-c',
        'core.hooksPath=/dev/null',
        '-c',
        'gc.auto=0',
        '-c',
        'advice.detachedHead=false',
        ...args,
      ],
      workingDirectory: workTree,
      stdoutEncoding: null,
    );
    return GitResult(
      result.exitCode,
      gitOutputText(result.stdout),
      gitOutputText(result.stderr),
      stdoutBytes: gitOutputBytes(result.stdout),
    );
  }
}

/// 非 git 环境的执行器：每条命令都失败，`available` 为假。
class UnavailableGitRunner implements GitRunner {
  const UnavailableGitRunner();

  @override
  Future<bool> available() async => false;

  @override
  Future<GitResult> run(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) async =>
      const GitResult(127, '', 'git 不可用');

  @override
  GitResult runSync(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) =>
      const GitResult(127, '', 'git 不可用');
}
