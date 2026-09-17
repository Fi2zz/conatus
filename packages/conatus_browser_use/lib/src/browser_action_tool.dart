/// 把 [SessionBrowser] 的一个工具接入 [ToolRegistry]。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tasks/conatus_tasks.dart';

import 'browser_tool_risk.dart';
import 'session_browser.dart';

/// 浏览器操作工具：调用转发到绑定 Session 的 [SessionBrowser]。
///
/// 工具的 schema、结果渲染、图像支持由 Provider 拥有，本工具只转发；
/// 风险等级由 [browserToolRisk] 声明，供审批门控读取。可选 seam（全为
/// null 时降级）：
///
/// - [taskCenter]：每次操作追踪为 `Task(kind: custom)`；
/// - [session]：操作记录为 `browser/action` 事件（`parentEventId` 串因果链）；
/// - [telemetry]：`browser.action.*` / `browser.navigation` / `browser.screenshot`
///   埋点。
class BrowserActionTool extends Tool {
  BrowserActionTool(
    this.browser,
    this.toolName, {
    this.session,
    this.taskCenter,
    this.telemetry,
  });

  /// 绑定的浏览器。
  final SessionBrowser browser;

  /// 工具名（Provider 拥有的名字）。
  final String toolName;

  /// 触发本工具的 Session（记录 `browser/action` 事件用）。
  final Session? session;

  /// 任务中心（可选）。
  final TaskCenter? taskCenter;

  /// 遥测导出器（可选）。
  final Telemetry? telemetry;

  @override
  String get name => toolName;

  @override
  String get description => '浏览器操作：$toolName（Session ${browser.sessionId}）';

  @override
  ToolRisk get riskLevel => browserToolRisk(toolName);

  @override
  Future<ToolResult> call(ToolContext context) async {
    final Map<String, Object?> args = context.arguments;
    final String? parentEventId =
        context.callId.isEmpty ? null : context.callId;
    _emitCalled(args);
    final Task? task = await _trackStart(args);
    try {
      final ToolResult result = await browser.call(toolName, args);
      await _trackEnd(task, result);
      _emitResult(result);
      _logAction(args, result, null, parentEventId);
      return result;
    } catch (error) {
      await _trackError(task, error);
      _emitFailed(error);
      _logAction(args, null, error, parentEventId);
      rethrow;
    }
  }

  Future<Task?> _trackStart(Map<String, Object?> args) async {
    final TaskCenter? center = taskCenter;
    if (center == null) return null;
    return center.create(
      kind: TaskKind.custom,
      description: '浏览器操作: $toolName',
      metadata: <String, Object?>{'sessionId': browser.sessionId, 'tool': toolName},
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

  void _emitCalled(Map<String, Object?> args) {
    telemetry?.emit(TelemetryEvent('browser.action.called',
        data: <String, Object?>{
          'tool': toolName,
          'session': browser.sessionId,
          'args': args,
        }));
    if (_isNavigation) {
      telemetry?.emit(TelemetryEvent('browser.navigation',
          data: <String, Object?>{'session': browser.sessionId}));
    }
    if (_isScreenshot) {
      telemetry?.emit(TelemetryEvent('browser.screenshot',
          data: <String, Object?>{'session': browser.sessionId}));
    }
  }

  void _emitResult(ToolResult result) {
    telemetry?.emit(TelemetryEvent('browser.action.completed',
        data: <String, Object?>{
          'tool': toolName,
          'isError': result.isError,
        }));
  }

  void _emitFailed(Object error) {
    telemetry?.emit(TelemetryEvent('browser.action.failed',
        data: <String, Object?>{'tool': toolName, 'error': '$error'}));
  }

  void _logAction(
    Map<String, Object?> args,
    ToolResult? result,
    Object? error,
    String? parentEventId,
  ) {
    final Session? owner = session;
    if (owner == null) return;
    owner.append(
      'browser/action',
      data: <String, Object?>{
        'tool': toolName,
        'args': args,
        'result': result == null ? null : resultToJson(result),
        'error': '$error',
      },
      parentEventId: parentEventId,
    );
  }

  bool get _isNavigation => toolName == 'browser_navigate';
  bool get _isScreenshot =>
      toolName == 'browser_take_screenshot' || toolName == 'browser_screenshot';
}

/// 把 [ToolResult] 投影为可 JSON 化的摘要。
Map<String, Object?> resultToJson(ToolResult result) => <String, Object?>{
      'isError': result.isError,
      'content': result.content,
      if (result.error != null) 'errorCode': result.error!.code,
    };
