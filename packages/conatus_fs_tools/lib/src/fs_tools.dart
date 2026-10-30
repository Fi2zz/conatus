import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'apply_patch.dart';
import 'edit_file.dart';
import 'glob_tool.dart';
import 'list_files.dart';
import 'read_file.dart';
import 'ripgrep_binary.dart';
import 'ripgrep_runner.dart';
import 'ripgrep_tool.dart';
import 'write_file.dart';

/// 遍历 / 列举时默认跳过的目录（按 basename）。
///
/// 只含通用依赖与构建目录；产品私有的配置 / 缓存目录由宿主通过
/// [FsToolOptions.skipDirs] 追加。
const Set<String> kDefaultSkipDirs = <String>{
  '.git',
  'node_modules',
  '.dart_tool',
  'build',
};

/// [provideFsTools] 的装配选项。
class FsToolOptions {
  const FsToolOptions({
    this.fs,
    this.tools,
    this.shell,
    this.ripgrep,
    this.runner,
    this.eviction,
    this.defaultReadLimit = 2000,
    this.maxReadChars = 200000,
    this.rgLimit = 50,
    this.enableSearch = true,
    this.enableList = true,
    this.enablePatch = false,
    this.skipDirs = kDefaultSkipDirs,
  });

  /// 文件系统接缝；缺省取上下文里的 `'fs'` 服务。
  final FileSystem? fs;

  /// 工具注册表；缺省取 `ctx.tools`。
  final ToolRegistry? tools;

  /// 子进程执行接缝；缺省取上下文里的 `'shell'` 服务。
  final ShellExecutor? shell;

  /// ripgrep 二进制；缺省调用 [RipgrepBinary.discover] 探测系统 / 打包 rg。
  final RipgrepBinary? ripgrep;

  /// ripgrep 执行接缝；缺省按平台选择：
  ///
  /// - Windows：用 [ProcessRipgrepRunner] 直接起本地进程（Windows 无 POSIX
  ///   单引号语义，经 shell 拼命令会坏）；要跑远程 shell 必须显式注入 runner。
  /// - 其它平台：有 `'shell'` 服务时用 [ShellRipgrepRunner]，没有则不注册 `grep`。
  ///
  /// 桌面端也可显式注入 [ProcessRipgrepRunner]（或自定义 runner）以避免命令
  /// 串经过 POSIX shell 引号解析。
  final RipgrepRunner? runner;

  /// 大结果落盘策略；供搜索工具使用。
  final ToolResultEviction? eviction;

  /// `read` 默认读取行数。
  final int defaultReadLimit;

  /// `read` 返回文本的最大字符数。
  final int maxReadChars;

  /// 搜索工具默认结果数上限。
  final int rgLimit;

  /// 是否注册搜索类工具（`glob` 等）。
  final bool enableSearch;

  /// 是否注册 `list`。
  final bool enableList;

  /// 是否注册 `apply_patch`（高风险补丁工具，默认关闭，由宿主显式开启）。
  final bool enablePatch;

  /// 遍历 / 列举时跳过的目录（按 basename）。
  final Set<String> skipDirs;
}

/// 注册文件系统工具到 `ctx.tools`，返回已注册的工具。
///
/// 依赖：
/// - `'fs'`：文件系统接缝（必需，除非 [FsToolOptions.fs] 已提供）
/// - `'tools'`：工具注册（必需，除非 [FsToolOptions.tools] 已提供）
///
/// 工具注册全部登记为上下文效应：上下文释放时自动撤销。
List<Tool> provideFsTools(
  Context ctx, {
  FsToolOptions options = const FsToolOptions(),
}) {
  final FileSystem resolvedFs = options.fs ?? ctx.require<FileSystem>('fs');
  final ToolRegistry registry = options.tools ?? ctx.tools;
  final List<Tool> registered = <Tool>[
    ReadFileTool(
      fs: resolvedFs,
      defaultLimit: options.defaultReadLimit,
      maxChars: options.maxReadChars,
    ),
    WriteFileTool(fs: resolvedFs),
    EditFileTool(fs: resolvedFs),
    if (options.enableList)
      ListFilesTool(fs: resolvedFs, skipDirs: options.skipDirs),
  ];
  if (options.enablePatch) {
    registered.add(ApplyPatchTool(fs: resolvedFs));
  }
  if (options.enableSearch) {
    registered.add(GlobTool(fs: resolvedFs, skipDirs: options.skipDirs));
    final ShellExecutor? shell =
        options.shell ?? ctx.get<ShellExecutor>('shell');
    final RipgrepRunner? runner = options.runner ?? _defaultRunner(shell);
    final RipgrepBinary? binary = options.ripgrep ?? RipgrepBinary.discover();
    if (runner != null && binary != null) {
      registered.add(RipgrepTool(
        runner: runner,
        binary: binary,
        eviction: options.eviction,
        limits: RipgrepLimits(defaultLimit: options.rgLimit),
      ));
    }
  }
  for (final Tool tool in registered) {
    ctx.effect(() => registry.register(tool));
  }
  return registered;
}

/// 默认 runner：Windows 直接起本地进程（无 POSIX 单引号语义），其余平台
/// 走 `'shell'` 接缝；要跑远程 shell 的 Windows 宿主必须显式注入 runner。
RipgrepRunner? _defaultRunner(ShellExecutor? shell) {
  if (Platform.isWindows) return const ProcessRipgrepRunner();
  return shell == null ? null : ShellRipgrepRunner(shell);
}
