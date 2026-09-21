/// coding 场景装配：读写 + 搜索复用 [provideFsTools]，执行层按需注册服务。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:conatus_tasks/conatus_tasks.dart';

import 'runtime/code_runtime.dart';
import 'tools/run_code_tool.dart';

/// 提供 coding 场景能力：读写层与搜索层复用 [provideFsTools]，执行层以
/// `'codeRuntime'` 服务 + `run_code` 工具注册（[enableRuntime] 且传入
/// [codeRuntime] 时）。
///
/// 依赖：
/// - `'fs'`：文件系统（必需）
/// - `'tools'`：工具注册（必需）
/// - `'shell'`：子进程执行（rg 必需；缺省或未发现 ripgrep 二进制时跳过 rg，
///   glob 仍注册）
/// - [eviction]：搜索结果落盘（可选，透传给 [provideFsTools]）
/// - [taskCenter] / [sessionLog] / [telemetry]：`run_code` 治理（可选，缺省
///   从上下文 `'tasks'` / `'sessionLogRecorder'` / `'telemetry'` 惰性取，
///   都没有则降级）
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
  TaskCenter? taskCenter,
  SessionLogRecorder? sessionLog,
  Telemetry? telemetry,
  bool enableSearch = true,
  bool enableRuntime = false,
  int rgLimit = 50,
}) {
  final ToolRegistry registry = tools ?? ctx.tools;
  final List<Tool> registered = provideFsTools(
    ctx,
    fs: fs,
    tools: registry,
    shell: shell,
    eviction: eviction,
    ripgrep: ripgrep,
    rgLimit: rgLimit,
    enableSearch: enableSearch,
  );
  if (enableRuntime && codeRuntime != null) {
    ctx.provide('codeRuntime', codeRuntime);
    ctx.onDispose(codeRuntime.dispose);
    final RunCodeTool tool = RunCodeTool(
      runtime: codeRuntime,
      tools: registry,
      taskCenter: taskCenter ?? ctx.get<TaskCenter>('tasks'),
      sessionLog:
          sessionLog ?? ctx.get<SessionLogRecorder>('sessionLogRecorder'),
      telemetry: telemetry ?? ctx.get<Telemetry>('telemetry'),
    );
    ctx.effect(() => registry.register(tool));
    registered.add(tool);
  }
  return registered;
}
