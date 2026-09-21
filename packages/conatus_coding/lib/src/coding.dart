/// coding 场景装配：读写 + 搜索复用 [provideFsTools]，执行层按需注册服务。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';

import 'runtime/code_runtime.dart';

/// 提供 coding 场景能力：读写层与搜索层复用 [provideFsTools]，
/// 执行层以 `'codeRuntime'` 服务注册（[enableRuntime] 且传入 [codeRuntime] 时）。
///
/// 依赖：
/// - `'fs'`：文件系统（必需）
/// - `'tools'`：工具注册（必需）
/// - `'shell'`：子进程执行（rg 必需；缺省或未发现 ripgrep 二进制时跳过 rg，
///   glob 仍注册）
/// - [eviction]：搜索结果落盘（可选，透传给 [provideFsTools]）
///
/// 返回已注册的工具列表；注册撤销由上下文生命周期统一管理。
List<Tool> provideCoding(
  Context ctx, {
  FileSystem? fs,
  ToolRegistry? tools,
  ShellExecutor? shell,
  ToolResultEviction? eviction,
  RipgrepBinary? ripgrep,
  CodeRuntime? codeRuntime,
  bool enableSearch = true,
  bool enableRuntime = false,
  int rgLimit = 50,
}) {
  final List<Tool> registered = provideFsTools(
    ctx,
    fs: fs,
    tools: tools,
    shell: shell,
    eviction: eviction,
    ripgrep: ripgrep,
    rgLimit: rgLimit,
    enableSearch: enableSearch,
  );
  if (enableRuntime && codeRuntime != null) {
    ctx.provide('codeRuntime', codeRuntime);
    ctx.onDispose(codeRuntime.dispose);
  }
  return registered;
}
