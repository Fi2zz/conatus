/// 桌面操作工具与风险映射（handoff-10 第 8 节）。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tasks/conatus_tasks.dart';

import 'desktop.dart';

/// 按工具名映射 [ToolRisk]。
///
/// - `low`：只读操作（截屏、列出屏幕/窗口、获取光标位置）；
/// - `high`：**所有输入操作**（鼠标、键盘、滚轮、窗口聚焦）。
///
/// 与 browser-use 不同，桌面操作**无法区分** `medium`——任何输入都可能
/// 产生不可逆的后果，因此一律 [ToolRisk.high]，走审批。
ToolRisk desktopToolRisk(String toolName) {
  if (_readOnly.contains(toolName)) return ToolRisk.low;
  return ToolRisk.high;
}

const Set<String> _readOnly = <String>{
  'screen_capture',
  'screen_list',
  'cursor_position',
  'window_list',
};

/// 桌面操作工具：调用转发到 [DesktopSession]。
///
/// 风险等级由 [desktopToolRisk] 声明（所有输入操作 high，走审批门控）。
/// 可选 seam（全为 null 时降级）：
///
/// - [taskCenter]：每次操作追踪为 `Task(kind: custom)`；
/// - [sessionLog] / [sessionId]：操作记录到触发它的 Session 日志
///   （`computer/action` 事件，`parentEventId` 串因果链；桌面操作本身
///   不绑定任何 Session）；
/// - [telemetry]：`computer.action.*` 埋点。
class DesktopActionTool extends Tool {
  DesktopActionTool(
    this.desktop,
    this.toolName, {
    this.sessionLog,
    this.sessionId,
    this.taskCenter,
    this.telemetry,
  });

  /// 桌面会话。
  final DesktopSession desktop;

  /// 工具名（Provider 拥有的名字）。
  final String toolName;

  /// 触发本操作的 Session 日志（可选）。
  final SessionLog? sessionLog;

  /// 触发本操作的 Session ID（记录事件归属；可选）。
  final String? sessionId;

  /// 任务中心（可选）。
  final TaskCenter? taskCenter;

  /// 遥测导出器（可选）。
  final Telemetry? telemetry;

  @override
  String get name => toolName;

  @override
  String get description => '桌面操作：$toolName';

  @override
  ToolRisk get riskLevel => desktopToolRisk(toolName);

  @override
  Future<ToolResult> call(ToolContext context) async {
    final Map<String, Object?> args = context.arguments;
    final String? parentEventId =
        context.callId.isEmpty ? null : context.callId;
    telemetry?.emit(TelemetryEvent('computer.action.called',
        data: <String, Object?>{'tool': toolName, 'args': args}));
    final Task? task = await _trackStart(args);
    try {
      final ToolResult result = await desktop.call(toolName, args);
      await _trackEnd(task, result);
      telemetry?.emit(TelemetryEvent('computer.action.completed',
          data: <String, Object?>{'tool': toolName}));
      unawaited(_logAction(args, result, null, parentEventId));
      return result;
    } catch (error) {
      await _trackError(task, error);
      telemetry?.emit(TelemetryEvent('computer.action.failed',
          data: <String, Object?>{'tool': toolName, 'error': '$error'}));
      unawaited(_logAction(args, null, error, parentEventId));
      rethrow;
    }
  }

  Future<Task?> _trackStart(Map<String, Object?> args) async {
    final TaskCenter? center = taskCenter;
    if (center == null) return null;
    return center.create(
      kind: TaskKind.custom,
      description: '桌面操作: $toolName',
      metadata: <String, Object?>{'tool': toolName},
    );
  }

  Future<void> _trackEnd(Task? task, ToolResult result) async {
    final TaskCenter? center = taskCenter;
    if (center == null || task == null) return;
    if (result.isError) {
      await center.update(task.id,
          status: TaskStatus.failed, error: result.error ?? result.content);
    } else {
      await center.update(task.id,
          status: TaskStatus.completed, result: result.value ?? result.content);
    }
  }

  Future<void> _trackError(Task? task, Object error) async {
    final TaskCenter? center = taskCenter;
    if (center == null || task == null) return;
    await center.update(task.id, status: TaskStatus.failed, error: '$error');
  }

  Future<void> _logAction(
    Map<String, Object?> args,
    ToolResult? result,
    Object? error,
    String? parentEventId,
  ) async {
    final SessionLog? log = sessionLog;
    final String? owner = sessionId;
    if (log == null || owner == null) return;
    await log.append(SessionEvent.create(
      sessionId: owner,
      type: 'computer/action',
      seq: 0,
      data: <String, Object?>{
        'tool': toolName,
        'args': args,
        'result': result == null ? null : resultToJson(result),
        'error': '$error',
      },
      parentEventId: parentEventId,
    ));
  }
}

/// 把 [ToolResult] 投影为可 JSON 化的摘要。
Map<String, Object?> resultToJson(ToolResult result) => <String, Object?>{
      'isError': result.isError,
      'content': result.content,
      if (result.error != null) 'errorCode': result.error!.code,
    };
