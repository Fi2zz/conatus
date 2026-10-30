import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'edit_file.dart';
import 'glob_tool.dart';
import 'list_files.dart';
import 'read_file.dart';
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
    this.eviction,
    this.defaultReadLimit = 2000,
    this.maxReadChars = 200000,
    this.rgLimit = 50,
    this.enableSearch = true,
    this.enableList = true,
    this.skipDirs = kDefaultSkipDirs,
  });

  /// 文件系统接缝；缺省取上下文里的 `'fs'` 服务。
  final FileSystem? fs;

  /// 工具注册表；缺省取 `ctx.tools`。
  final ToolRegistry? tools;

  /// 子进程执行接缝；供后续接入的搜索工具使用。
  final ShellExecutor? shell;

  /// 大结果落盘策略；供后续接入的搜索工具使用。
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
  if (options.enableSearch) {
    registered.add(GlobTool(fs: resolvedFs, skipDirs: options.skipDirs));
  }
  for (final Tool tool in registered) {
    ctx.effect(() => registry.register(tool));
  }
  return registered;
}
