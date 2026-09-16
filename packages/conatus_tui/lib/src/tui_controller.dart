/// TUI 会话控制器：把 conatus 的 [Context] / [SessionStore] / Agent Loop 桥接到
/// nocterm 组件，处理斜杠命令、会话切换与屏上记录的投射。
///
/// 设计要点：一个有界子上下文（`plugin('tui-session:<id>')`）承载当前会话的
/// Agent Loop —— 切换会话即释放旧子上下文、建立新子上下文，效应随上下文自动
/// 撤销，无需手工清理。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_schedule/conatus_schedule.dart';

import 'transcript.dart';
import 'tui_help.dart';
import 'tui_message.dart';
import 'tui_session_picker.dart';

/// 会话 id 规则：字母 / 数字 / 下划线 / 中文 / 短横，长度 1—64。
bool isValidSessionId(String id) =>
    RegExp(r'^[A-Za-z0-9_\-\u4e00-\u9fff]{1,64}$').hasMatch(id);

/// TUI 会话控制器。
class ConatusTuiController {
  ConatusTuiController({
    required Context app,
    required SessionStore sessions,
    required this.name,
    required String initialSession,
    required this.modelLabel,
    this.onExit,
  })  : _app = app,
        _sessions = sessions,
        _sessionId = initialSession {
    picker = TuiSessionPicker(sessions, onChanged: _refresh);
  }

  final Context _app;
  final SessionStore _sessions;

  /// 顶栏展示的场景名。
  final String name;

  /// 顶栏展示的模型标签。
  final String modelLabel;

  /// 退出请求（`/exit`、`/quit`、Ctrl+C）；由宿主接 `shutdownApp`。
  final void Function()? onExit;

  /// 屏上记录。
  final Transcript transcript = Transcript();

  /// 会话选择面板。
  late final TuiSessionPicker picker;

  /// 状态变化通知（组件据此 `setState`）。
  void Function()? onChanged;

  String _sessionId;
  Session? _session;
  Context? _sessionCtx;
  AgentLoop? _agent;
  Disposer? _eventSub;

  /// 在飞轮次的取消句柄（Esc / 打断）；null = 无在飞轮次。
  AgentCancel? _cancel;

  /// 是否有在途轮次。
  bool busy = false;

  /// 会话是否已绑定就绪。
  bool ready = false;

  /// 当前会话 id。
  String get sessionId => _sessionId;

  /// 绑定初始会话。
  Future<void> start() async {
    await _bind(_sessionId);
    _refresh();
  }

  /// 释放当前会话绑定（幂等）。
  void dispose() => _unbind();

  /// 处理一行输入：斜杠命令本地处理，其余进对话链路。
  Future<void> handleLine(String raw) async {
    final String line = raw.trim();
    if (line.isEmpty) {
      return;
    }
    if (line.startsWith('/')) {
      final String rest = line.replaceFirst(RegExp('^/+'), '');
      final int space = rest.indexOf(' ');
      final String command = space < 0 ? rest : rest.substring(0, space);
      final String arg = space < 0 ? '' : rest.substring(space + 1).trim();
      await _handleCommand(command, arg);
      return;
    }
    await submit(line);
  }

  /// 打断在飞轮次（Esc / barge-in）：取消模型与工具等待，盘上记录保留。
  void interrupt() => _cancel?.cancel();

  /// 提交一轮对话。
  Future<void> submit(String text) async {
    if (busy) {
      transcript.add(TuiRole.system, '正在回复，请稍候（Esc 可打断）。');
      _refresh();
      return;
    }
    final AgentLoop? agent = _agent;
    if (agent == null) {
      transcript.add(TuiRole.system, '会话尚未就绪，请稍候。');
      _refresh();
      return;
    }
    final AgentCancel cancel = AgentCancel();
    _cancel = cancel;
    busy = true;
    _refresh();
    try {
      await agent.run(text, cancel: cancel);
    } on AgentCancelled {
      transcript.add(TuiRole.system, '已打断这一轮。');
    } on LlmException catch (error) {
      transcript.add(TuiRole.system, '模型调用失败：${error.message}');
    } catch (error) {
      transcript.add(TuiRole.system, '出错：$error');
    } finally {
      _cancel = null;
      busy = false;
      await _afterTurn();
      _refresh();
    }
  }

  /// 打开 / 关闭 / 移动会话面板。
  Future<void> openPicker() => picker.show(_sessionId);
  void closePicker() => picker.close();
  void movePicker(int delta) => picker.move(delta);

  /// 确认选择：切到选中会话并关闭面板。
  Future<void> pickSelected() async {
    final String? id = picker.selectedId();
    picker.close();
    if (id != null) {
      await switchSession(id);
    }
  }

  /// 切换会话：不存在则懒建（各自文件与历史）；非法 id 只提示不切换。
  Future<void> switchSession(String id, {String? announce}) async {
    if (!isValidSessionId(id)) {
      transcript.add(TuiRole.system, '会话 id 非法：只允许字母/数字/下划线/中文/短横，长度 1—64。');
      _refresh();
      return;
    }
    if (ready && id == _sessionId) {
      transcript.add(TuiRole.system, '已在会话 $_sessionId。');
      _refresh();
      return;
    }
    _unbind();
    _sessionId = id;
    await _bind(id);
    transcript.add(
      TuiRole.system,
      announce ?? '已切换到会话 $_sessionId（数据文件：$_sessionId.jsonl）。',
    );
    _refresh();
  }

  /// 开启新会话。
  Future<void> newSession() async {
    final Session session = _sessions.create();
    await switchSession(
      session.id,
      announce: '已开启新会话 ${session.id}（上一会话已保存，/sessions 可切回）。',
    );
  }

  Future<void> _handleCommand(String command, String arg) async {
    switch (command) {
      case 'quit' || 'exit':
        onExit?.call();
      case 'help':
        transcript.add(TuiRole.system, tuiHelpText);
      case 'new':
        await newSession();
      case 'sessions':
        await openPicker();
      case 'session':
        if (arg.isEmpty) {
          await openPicker();
        } else {
          await switchSession(arg);
        }
      case 'tools':
        _showTools();
      case 'remember':
        await _remember(arg);
      case 'forget':
        await _forget(arg);
      case 'telemetry':
        _showTelemetry();
      case 'clear':
        transcript.clear();
      default:
        transcript.add(TuiRole.system, '未知命令：/$command（/help 查看可用命令）');
    }
    _refresh();
  }

  void _showTools() {
    final ToolRegistry? tools = _app.get<ToolRegistry>('tools');
    if (tools == null || tools.names.isEmpty) {
      transcript.add(TuiRole.system, '当前没有已注册工具。');
      return;
    }
    transcript.add(
      TuiRole.system,
      '已注册工具（${tools.names.length}）：${tools.names.join('、')}',
    );
  }

  /// `/remember <内容>`：直接调用记忆能力，绕过模型。
  Future<void> _remember(String arg) async {
    final MemoryStore? memory = _app.get<MemoryStore>('memory');
    if (memory == null) {
      transcript.add(TuiRole.system, '记忆服务不可用。');
      return;
    }
    final String text = arg.trim();
    if (text.isEmpty) {
      transcript.add(TuiRole.system, '用法：/remember <要记住的内容>');
      return;
    }
    final MemoryEntry entry = await memory.remember(text, tags: {'explicit'});
    transcript.add(TuiRole.system, '已记住（id=${entry.id}）。');
  }

  /// `/forget <id 或 关键字>`：直接调用遗忘能力，绕过模型。
  Future<void> _forget(String arg) async {
    final MemoryStore? memory = _app.get<MemoryStore>('memory');
    if (memory == null) {
      transcript.add(TuiRole.system, '记忆服务不可用。');
      return;
    }
    final String query = arg.trim();
    if (query.isEmpty) {
      transcript.add(TuiRole.system, '用法：/forget <id 或 关键字>');
      return;
    }
    if (await memory.forget(query)) {
      transcript.add(TuiRole.system, '已遗忘 id="$query"。');
      return;
    }
    final int deleted = await memory.forgetMatching(query);
    if (deleted == 0) {
      transcript.add(TuiRole.system, '未找到匹配 "$query" 的记忆。');
      return;
    }
    transcript.add(TuiRole.system, '已遗忘 $deleted 条匹配 "$query" 的记忆。');
  }

  void _showTelemetry() {
    final Telemetry? telemetry = _app.get<Telemetry>('telemetry');
    if (telemetry is! InMemoryTelemetry) {
      transcript.add(TuiRole.system, '遥测服务不可用。');
      return;
    }
    final List<TelemetryEvent> recent = telemetry.recent;
    if (recent.isEmpty) {
      transcript.add(TuiRole.system, '尚无遥测事件。');
      return;
    }
    final Iterable<String> names = recent
        .skip(recent.length > 8 ? recent.length - 8 : 0)
        .map((TelemetryEvent event) => event.name);
    transcript.add(TuiRole.system, '最近遥测：${names.join('、')}');
  }

  Future<void> _bind(String id) async {
    final Session session = await _sessions.open(id);
    _session = session;
    final Context ctx = _app.plugin('tui-session:$id', (Context child) {
      provideAgentLoop(child, session: session);
      provideSessionSchedule(child, session: session, sessions: _sessions);
      provideScheduleTools(child);
      provideScheduleRuntime(child, deliver: _deliverReminder);
    });
    _sessionCtx = ctx;
    _agent = ctx.agentLoop;
    transcript.rebuildFrom(session);
    _eventSub = session.onEvent((SessionEvent event) {
      transcript.apply(event);
      _refresh();
    });
    ready = true;
  }

  void _unbind() {
    _eventSub?.call();
    _eventSub = null;
    _sessionCtx?.dispose();
    _sessionCtx = null;
    _agent = null;
    _session = null;
    ready = false;
  }

  Future<void> _afterTurn() async {
    await _sessions.flush();
    final RecoveryService? recovery = _app.get<RecoveryService>('recovery');
    final Session? session = _session;
    if (recovery != null && session != null && !session.closed) {
      try {
        await recovery.snapshot(session);
      } catch (error) {
        transcript.add(TuiRole.system, '快照保存失败：$error');
      }
    }
    // 轮次结束即空闲：让到期的提醒立刻交付，而不必等到下一次定时唤醒。
    _sessionCtx?.get<ScheduleRuntime>('scheduleRuntime')?.requestDrive();
  }

  /// 调度交付：空闲时把提醒当作一轮用户输入投递，返回是否成功入队。
  ///
  /// 忙时返回 `false`，调度器不会记录派发，记录保持活动并在下一次触发时重试。
  Future<bool> _deliverReminder(String text) async {
    if (busy || _agent == null) return false;
    unawaited(submit(text));
    return true;
  }

  void _refresh() => onChanged?.call();
}
