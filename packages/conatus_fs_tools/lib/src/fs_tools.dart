import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'edit_file.dart';
import 'glob_tool.dart';
import 'read_file.dart';
import 'ripgrep_binary.dart';
import 'ripgrep_tool.dart';
import 'write_file.dart';

/// 注册文件系统工具到 `ctx.tools`，返回已注册的工具。
///
/// 依赖：
/// - `'fs'`：文件系统接缝（必需）
/// - `'tools'`：工具注册（必需）
/// - `'shell'`：子进程执行（rg 必需；缺省或未发现 ripgrep 二进制时跳过 rg，
///   glob 仍注册）
/// - [eviction]：搜索结果落盘（可选；未提供时依赖全局
///   `tool-result-eviction` 中间件兜底）
List<Tool> provideFsTools(
  Context ctx, {
  FileSystem? fs,
  ToolRegistry? tools,
  ShellExecutor? shell,
  ToolResultEviction? eviction,
  RipgrepBinary? ripgrep,
  int defaultReadLimit = 2000,
  int maxReadChars = 200000,
  int rgLimit = 50,
  bool enableSearch = true,
}) {
  final FileSystem resolvedFs = fs ?? ctx.require<FileSystem>('fs');
  final ToolRegistry registry = tools ?? ctx.tools;
  final List<Tool> registered = <Tool>[
    ReadFileTool(fs: resolvedFs, defaultLimit: defaultReadLimit, maxChars: maxReadChars),
    WriteFileTool(fs: resolvedFs),
    EditFileTool(fs: resolvedFs),
  ];
  if (enableSearch) {
    registered.addAll(_searchTools(
      ctx,
      resolvedFs,
      shell: shell,
      eviction: eviction,
      ripgrep: ripgrep,
      rgLimit: rgLimit,
    ));
  }
  for (final Tool tool in registered) {
    ctx.effect(() => registry.register(tool));
  }
  return registered;
}

/// 搜索工具：glob 始终注册；shell 与 rg 二进制齐备时才注册 rg。
List<Tool> _searchTools(
  Context ctx,
  FileSystem fs, {
  ShellExecutor? shell,
  ToolResultEviction? eviction,
  RipgrepBinary? ripgrep,
  required int rgLimit,
}) {
  final List<Tool> tools = <Tool>[GlobTool(fs: fs)];
  final ShellExecutor? resolvedShell = shell ?? ctx.get<ShellExecutor>('shell');
  if (resolvedShell == null) return tools;
  final RipgrepBinary? binary = ripgrep ?? RipgrepBinary.discover();
  if (binary == null) return tools;
  tools.add(RipgrepTool(
    shell: resolvedShell,
    binary: binary,
    eviction: eviction,
    defaultLimit: rgLimit,
  ));
  return tools;
}
