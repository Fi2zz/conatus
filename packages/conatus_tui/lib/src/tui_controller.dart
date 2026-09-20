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
import 'package:conatus_cron/conatus_cron.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_schedule/conatus_schedule.dart';
import 'package:conatus_skill/conatus_skill.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:conatus_tts/conatus_tts.dart';

import 'ask_user_tool.dart';
import 'team_snapshot.dart';
import 'team_subscription.dart';
import 'transcript.dart';
import 'tui_choice.dart';
import 'tui_commands.dart';
import 'tui_help.dart';
import 'tui_message.dart';
import 'tui_options.dart';
import 'tui_permission.dart';
import 'tui_permission_gate.dart';
import 'tui_session_picker.dart';
import 'tui_skill_command.dart';
import 'voice_reporter.dart';

/// `/goal` 用法提示。
const String kGoalUsage =
    '用法：/goal [status|set <文本>|edit <文本>|pause|resume|done|clear]';

/// `/cron` 用法提示。
const String kCronUsage = '用法：/cron [list|add <内容> <at|every|daily|cron> <规则>|'
    'remove <id>|enable <id>|disable <id>|history [条数]]\n'
    '规则：at=ISO 时刻；every=秒或 10分钟/1小时；daily/每天=HH:MM；'
    '每周X=HH:MM；cron=5 段表达式';

/// `/team` 用法提示。
const String kTeamUsage = '用法：/team [status|interrupt <成员 id>]';

/// `/task` 用法提示。
const String kTaskUsage = '用法：/task [claim <任务 id>|release <任务 id>]';

/// TUI 会话控制器。
class ConatusTuiController implements TuiUserPromptHost {
  ConatusTuiController({
    required Context app,
    required SessionStore sessions,
    required this.name,
    required String initialSession,
    required this.modelLabel,
    this.onExit,
    this.tts,
    this.ttsSink,
  })  : _app = app,
        _sessions = sessions,
        _sessionId = initialSession {
    picker = TuiSessionPicker(sessions, onChanged: _refresh);
    _app.provide('tuiController', this);
    final TuiPermissionGate? gate = app.get<TuiPermissionGate>('approval');
    _gate = gate;
    choice.onChanged = _refresh;
    _syncPermissionMode();
  }

  final Context _app;
  final SessionStore _sessions;

  /// 选项浮层（`ask_user` 与工具审批共用）。
  ///
  /// 优先复用根上下文里已提供的 `'tuiChoice'`（审批门持有的是同一个），
  /// 未提供时自建一个。
  @override
  late final TuiChoicePrompt choice =
      _app.get<TuiChoicePrompt>('tuiChoice') ?? TuiChoicePrompt();

  late final TuiPermissionGate? _gate;

  /// 顶栏展示的场景名。
  final String name;

  /// 顶栏展示的模型标签。
  final String modelLabel;

  /// 退出请求（`/exit`、`/quit`、Ctrl+C）；由宿主接 `shutdownApp`。
  final void Function()? onExit;

  /// TTS 服务（可选）。注入后随会话装配团队语音播报。
  final TtsService? tts;

  /// TTS 音频输出目标（可选）。缺省 no-op，桌面 TUI 无声。
  final TtsAudioSink? ttsSink;

  /// 会话装配钩子：会话子上下文与 Session 建好、内置插件提供完毕后回调。
  ///
  /// 宿主可在此往该会话的子上下文里挂自己的插件/服务（如提供 'tasks' 任务中心）。
  /// 缺省 null，不注入时行为与接入前一致。随会话绑定调用一次；切会话时子上下文
  /// 释放，钩子里登记的效应自动撤销。
  void Function(Context sessionCtx, Session session)? configureSession;

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
  PlanMode? _planMode;
  GoalService? _goal;
  Disposer? _eventSub;

  /// 在飞轮次的取消句柄（Esc / 打断）；null = 无在飞轮次。
  AgentCancel? _cancel;

  /// 团队订阅（随会话绑定/解绑）。
  TeamSubscription? _teamSub;

  /// 团队语音播报（随会话绑定/解绑；tts 注入时启用）。
  VoiceReporter? _voice;

  /// 当前权限模式下挂着的审批中间件撤销句柄；Never Ask 时为 `null`。
  Disposer? _approvalGate;

  /// 当前权限模式（随绑定的会话变化）。
  TuiPermissionMode _permissionMode = TuiPermissionMode.askWhenNeeded;

  /// 是否有在途轮次。
  bool busy = false;

  /// 会话是否已绑定就绪。
  bool ready = false;

  /// 当前会话 id。
  String get sessionId => _sessionId;

  /// 当前权限模式。
  @override
  TuiPermissionMode get permissionMode => _permissionMode;

  /// 状态栏展示的权限模式名。
  String get permissionLabel => _permissionMode.label;

  /// 团队状态快照（未装配团队或未绑定时为空）。
  TeamSnapshot get teamSnapshot => _teamSub?.snapshot ?? const TeamSnapshot();

  /// 切换权限模式：持久化到当前会话、按新阈值重挂审批中间件并提示。
  ///
  /// 会话未绑定时拒绝：此时既无法持久化、模式也会在绑定后被恢复逻辑覆盖，
  /// 静默生效只会让界面提示与实际状态不符。
  @override
  void applyPermissionMode(TuiPermissionMode mode) {
    final Session? session = _session;
    if (session == null) {
      transcript.add(TuiRole.system, '会话尚未就绪，权限模式未切换。');
      _refresh();
      return;
    }
    if (mode == _permissionMode && _approvalGate != null) {
      return;
    }
    _permissionMode = mode;
    session.append(kPermissionModeEvent, data: <String, Object?>{'mode': mode.name});
    _syncPermissionMode();
    transcript.add(TuiRole.system, '权限模式已切换为「${mode.label}」：${mode.description}');
    _refresh();
  }

  /// 按当前模式挂载 / 卸载审批中间件（幂等）。
  void _syncPermissionMode() {
    _approvalGate?.call();
    _approvalGate = null;
    final TuiPermissionGate? gate = _gate;
    final ToolRisk? threshold = _permissionMode.threshold;
    if (gate == null || threshold == null) {
      return;
    }
    _approvalGate = instrumentApproval(
      _app,
      approval: gate,
      threshold: threshold,
      timeout: kTuiDecisionTimeout,
    );
  }

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
    bool turnOk = true;
    String reply = '';
    try {
      final AgentTurn turn = await agent.run(text, cancel: cancel);
      reply = turn.reply;
    } on AgentCancelled {
      turnOk = false;
      transcript.add(TuiRole.system, '已打断这一轮。');
    } on LlmException catch (error) {
      turnOk = false;
      transcript.add(TuiRole.system, '模型调用失败：${error.message}');
    } catch (error) {
      turnOk = false;
      transcript.add(TuiRole.system, '出错：$error');
    } finally {
      _cancel = null;
      // 同步收尾先行：轮询 busy 的调用方（如 cron 交付）在置闲后即可看到
      // 运行记录已是终态。
      _settleCronRuns(ok: turnOk, reply: reply);
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
        transcript.add(TuiRole.system, buildTuiHelpText(extra: _skillCommands));
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
      case 'plan':
        _togglePlanMode();
      case 'goal':
        await _handleGoal(arg);
      case 'cron':
        await _handleCron(arg);
      case 'team':
        await _handleTeam(arg);
      case 'task':
        await _handleTask(arg);
      case 'remember':
        await _remember(arg);
      case 'forget':
        await _forget(arg);
      case 'telemetry':
        _showTelemetry();
      case 'clear':
        transcript.clear();
      default:
        // 静态命令都不匹配时，把命令词当作技能名试一次。
        if (!await _runSkill(command, arg)) {
          transcript.add(
              TuiRole.system, '未知命令：/$command（/help 查看可用命令）');
        }
    }
    _refresh();
  }

  /// 当前可用的斜杠命令：静态表 + 技能注册表投影出的技能命令。
  List<TuiCommand> get commands => <TuiCommand>[...tuiCommands, ..._skillCommands];

  List<TuiCommand> get _skillCommands =>
      skillTuiCommands(_app.get<SkillRegistry>('skillRegistry'));

  /// 把 `/<技能名> [补充要求]` 当作技能调用；不是已知技能时返回 `false`。
  ///
  /// 展开后的正文块作为一轮用户输入交给 Agent Loop，因此照常进
  /// `user/message` 事件；屏上由 [collapseSkillPrompt] 折叠回一行。
  Future<bool> _runSkill(String name, String arg) async {
    final SkillRegistry? registry = _app.get<SkillRegistry>('skillRegistry');
    if (registry == null) return false;
    final SkillDefinition? definition = await registry.load(name);
    if (definition == null) return false;
    transcript.add(TuiRole.system, '已展开技能 `$name`，交给模型执行。');
    await submit(renderSkillPrompt(definition, arg));
    return true;
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

  /// `/plan`：进入 / 退出 Plan Mode（先规划、经 exit_plan_mode 提交后执行）。
  void _togglePlanMode() {
    final PlanMode? planMode = _planMode;
    if (planMode == null) {
      transcript.add(TuiRole.system, 'Plan Mode 不可用：会话尚未绑定。');
      return;
    }
    if (planMode.state == PlanModeState.active) {
      planMode.exit();
      transcript.add(TuiRole.system, '已退出 Plan Mode。');
      return;
    }
    planMode.enter();
    final String reviewNote = _app.has('approval')
        ? '计划经 exit_plan_mode 提交后等待审批。'
        : '计划经 exit_plan_mode 提交后即获批执行（未配置审批端口）。';
    transcript.add(
        TuiRole.system, '已进入 Plan Mode：有副作用的工具被拦截，模型先规划再执行。$reviewNote');
  }

  /// `/goal [子命令]`：管理当前会话的长期目标（不经模型，直接调 Goal 服务）。
  Future<void> _handleGoal(String arg) async {
    final GoalService? goal = _goal;
    if (goal == null) {
      transcript.add(TuiRole.system, 'Goal 不可用：会话尚未绑定。');
      return;
    }
    final int space = arg.indexOf(' ');
    final String sub = space < 0 ? arg.trim() : arg.substring(0, space).trim();
    final String rest = space < 0 ? '' : arg.substring(space + 1).trim();
    try {
      await _runGoalSub(goal, sub, rest);
    } on GoalException catch (e) {
      transcript.add(TuiRole.system, '目标操作失败：${e.message}');
    }
  }

  Future<void> _runGoalSub(GoalService goal, String sub, String rest) async {
    switch (sub) {
      case '' || 'status':
        final Goal? current = goal.current;
        transcript.add(
          TuiRole.system,
          current == null
              ? '当前没有目标。用 /goal set <文本> 创建。'
              : _goalStatusText(current),
        );
      case 'set':
        if (rest.isEmpty) {
          transcript.add(TuiRole.system, kGoalUsage);
          return;
        }
        final Goal created = await goal.create(rest);
        transcript.add(TuiRole.system, '已创建目标：${created.text}');
      case 'edit':
        if (rest.isEmpty) {
          transcript.add(TuiRole.system, kGoalUsage);
          return;
        }
        final Goal edited = await goal.edit(rest);
        transcript.add(TuiRole.system, '目标已更新：${edited.text}');
      case 'pause':
        await goal.pause();
        transcript.add(TuiRole.system, '目标已暂停。');
      case 'resume':
        await goal.resume();
        transcript.add(TuiRole.system, '目标已恢复推进。');
      case 'done':
        await goal.complete();
        transcript.add(TuiRole.system, '目标已完成。');
      case 'clear':
        await goal.clear();
        transcript.add(TuiRole.system, '目标已清除。');
      default:
        transcript.add(TuiRole.system, kGoalUsage);
    }
  }

  String _goalStatusText(Goal goal) {
    final StringBuffer buffer = StringBuffer()
      ..write('当前目标：${goal.text}\n状态：${goal.status.name}')
      ..write('｜轮次：${goal.round} / ${goal.maxRounds}');
    if (goal.blockReason != null) {
      buffer.write('\n阻塞原因：${goal.blockReason}');
    }
    return buffer.toString();
  }

  /// `/cron [子命令]`：不经模型直接管理定时任务。
  Future<void> _handleCron(String arg) async {
    final CronService? cron = _app.get<CronService>('cron');
    if (cron == null) {
      transcript.add(TuiRole.system, '定时任务不可用：未装配 cron 服务。');
      return;
    }
    final int space = arg.indexOf(' ');
    final String sub = space < 0 ? arg.trim() : arg.substring(0, space).trim();
    final String rest = space < 0 ? '' : arg.substring(space + 1).trim();
    try {
      await _runCronSub(cron, sub, rest);
    } on CronException catch (e) {
      transcript.add(TuiRole.system, '定时任务操作失败：${e.message}');
    }
  }

  Future<void> _runCronSub(CronService cron, String sub, String rest) async {
    switch (sub) {
      case '' || 'list':
        _showCronTasks(cron);
      case 'add':
        _cronAdd(cron, rest);
      case 'remove':
        _cronRemove(cron, rest);
      case 'enable':
        _cronSetEnabled(cron, rest, enabled: true);
      case 'disable':
        _cronSetEnabled(cron, rest, enabled: false);
      case 'history':
        _showCronHistory(cron, rest);
      default:
        transcript.add(TuiRole.system, kCronUsage);
    }
  }

  void _cronAdd(CronService cron, String rest) {
    final Map<String, Object?>? input = _parseCronAdd(rest);
    if (input == null) {
      transcript.add(TuiRole.system, kCronUsage);
      return;
    }
    final CronTaskView view =
        cron.addDynamicTask(input, callerSessionId: _sessionId);
    transcript.add(TuiRole.system, '已添加定时任务 ${view.id}。');
  }

  /// 解析 `/cron add` 的 `<内容> <at|every|daily|cron> <规则>`；形状不符返回 null。
  ///
  /// 规则在末尾：`at` / `every` / `daily` 各 1 个 token，`cron` 表达式 5 个 token
  /// （含空格），内容可含任意空格。规则词接受中文别名：`每天` / `每日` / `每隔` /
  /// `每周X`；`every` 间隔可带单位（10分钟 / 1小时）。
  Map<String, Object?>? _parseCronAdd(String rest) {
    final List<String> parts = rest
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.length < 3) return null;
    if (parts.length >= 7 && parts[parts.length - 6] == 'cron') {
      return <String, Object?>{
        'prompt': parts.sublist(0, parts.length - 6).join(' '),
        'cron': parts.sublist(parts.length - 5).join(' '),
      };
    }
    // `every 10 分钟`：数字与单位分空格，合并尾部两 token。
    if (parts.length >= 4 && _isEvery(parts[parts.length - 3])) {
      final num? seconds = _parseInterval(
          '${parts[parts.length - 2]} ${parts[parts.length - 1]}');
      if (seconds != null) {
        return <String, Object?>{
          'prompt': parts.sublist(0, parts.length - 3).join(' '),
          'every': seconds,
        };
      }
    }
    final String prompt = parts.sublist(0, parts.length - 2).join(' ');
    final String kind = parts[parts.length - 2];
    final String value = parts[parts.length - 1];
    final String? weekday = _weeklyWeekday(kind);
    if (weekday != null) {
      final String? cron = _dailyCron(value, weekday);
      return cron == null
          ? null
          : <String, Object?>{'prompt': prompt, 'cron': cron};
    }
    return switch (kind) {
      'at' => <String, Object?>{'prompt': prompt, 'at': value},
      'daily' || '每天' || '每日' =>
        <String, Object?>{'prompt': prompt, 'daily': value},
      'every' || '每隔' => _parseEvery(prompt, value),
      _ => null,
    };
  }

  bool _isEvery(String kind) => kind == 'every' || kind == '每隔';

  /// 间隔文本 → 秒；纯秒数或「数字 + 单位」。
  num? _parseInterval(String raw) {
    final String text = raw.trim().toLowerCase();
    if (text.isEmpty) return null;
    final num? plain = num.tryParse(text);
    if (plain != null) return plain;
    final RegExpMatch? match = RegExp(
      r'^(\d+(?:\.\d+)?)\s*(秒|s|分钟|分|min|mins|m|小时|时|h|hour|hours)$',
    ).firstMatch(text);
    if (match == null) return null;
    final double value = double.parse(match[1]!);
    return switch (match[2]!) {
      '秒' || 's' => value,
      '分钟' || '分' || 'min' || 'mins' || 'm' => value * 60,
      '小时' || '时' || 'h' || 'hour' || 'hours' => value * 3600,
      _ => null,
    };
  }

  Map<String, Object?>? _parseEvery(String prompt, String value) {
    final num? seconds = _parseInterval(value);
    if (seconds == null) return null;
    return <String, Object?>{'prompt': prompt, 'every': seconds};
  }

  /// `每周X` → cron 星期数（'1'-'6' 周一~六，'0' 周日）；非每周X 返回 null。
  String? _weeklyWeekday(String kind) {
    final RegExpMatch? match =
        RegExp(r'^每周([一二三四五六日天])$').firstMatch(kind);
    if (match == null) return null;
    return switch (match.group(1)!) {
      '一' => '1',
      '二' => '2',
      '三' => '3',
      '四' => '4',
      '五' => '5',
      '六' => '6',
      _ => '0',
    };
  }

  /// `HH:MM` + cron 星期数 → cron 表达式 `分 时 * * 星期`。
  String? _dailyCron(String value, String weekday) {
    final RegExpMatch? match = kCronDailyPattern.firstMatch(value);
    if (match == null) return null;
    return '${int.parse(match[2]!)} ${int.parse(match[1]!)} * * $weekday';
  }

  void _cronRemove(CronService cron, String id) {
    if (id.isEmpty) {
      transcript.add(TuiRole.system, kCronUsage);
      return;
    }
    cron.removeDynamicTask(id);
    transcript.add(TuiRole.system, '已删除定时任务 $id。');
  }

  void _cronSetEnabled(CronService cron, String id, {required bool enabled}) {
    if (id.isEmpty) {
      transcript.add(TuiRole.system, kCronUsage);
      return;
    }
    final CronTaskView view = cron.setEnabled(id, enabled);
    transcript.add(TuiRole.system, '已${enabled ? '启用' : '停用'}定时任务 ${view.id}。');
  }

  void _showCronTasks(CronService cron) {
    final List<CronTaskView> tasks = cron.listTasks();
    if (tasks.isEmpty) {
      transcript.add(TuiRole.system, '当前没有定时任务。');
      return;
    }
    final StringBuffer buffer = StringBuffer('定时任务（${tasks.length}）：');
    for (final CronTaskView view in tasks) {
      buffer
        ..write('\n  ${view.id} [${view.enabled ? '启用' : '停用'}] '
            '${_cronScheduleText(view)}')
        ..write(view.nextRunAt == null
            ? ''
            : ' 下次=${_formatLocal(view.nextRunAt!)}')
        ..write(' 内容=${view.prompt}');
    }
    transcript.add(TuiRole.system, buffer.toString());
  }

  String _cronScheduleText(CronTaskView view) {
    final MapEntry<String, Object?> entry = view.schedule.entries.first;
    final String value = '${entry.value}';
    return switch (entry.key) {
      'at' => 'at $value',
      'everySeconds' => 'every ${value}s',
      'daily' => 'daily $value',
      _ => 'cron $value',
    };
  }

  void _showCronHistory(CronService cron, String rest) {
    final int? limit = int.tryParse(rest);
    final List<CronRunRecord> records = cron.listHistory(limit: limit ?? 10);
    if (records.isEmpty) {
      transcript.add(TuiRole.system, '尚无定时任务运行记录。');
      return;
    }
    final StringBuffer buffer = StringBuffer('运行记录（最新在前）：');
    for (final CronRunRecord record in records) {
      buffer
        ..write('\n  #${record.seq} ${record.taskId} '
            '${_cronStatusText(record.status)} 排期=${_formatLocal(record.scheduledFor)}')
        ..write(record.excerpt == null ? '' : ' 结果=${record.excerpt}');
    }
    transcript.add(TuiRole.system, buffer.toString());
  }

  String _cronStatusText(String status) => switch (status) {
        CronRunStatus.completed => '完成',
        CronRunStatus.failed => '失败',
        CronRunStatus.delivered => '已交付',
        _ => status,
      };

  /// 本地时区的 `yyyy-MM-dd HH:mm` 展示。
  String _formatLocal(DateTime instant) {
    final DateTime local = instant.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
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

  /// `/team [status|interrupt <id>]`：团队状态摘要与成员管理（不经模型）。
  Future<void> _handleTeam(String arg) async {
    final AgentTeam? team = _sessionCtx?.get<AgentTeam>('team');
    if (team == null) {
      transcript.add(TuiRole.system, '团队不可用：会话尚未装配团队服务。');
      return;
    }
    final int space = arg.indexOf(' ');
    final String sub = space < 0 ? arg.trim() : arg.substring(0, space).trim();
    final String rest = space < 0 ? '' : arg.substring(space + 1).trim();
    try {
      switch (sub) {
        case '' || 'status':
          transcript.add(TuiRole.system, summarizeTeamProgress(teamSnapshot));
        case 'interrupt':
          if (rest.isEmpty) {
            transcript.add(TuiRole.system, kTeamUsage);
            return;
          }
          await team.interrupt(rest);
          transcript.add(TuiRole.system, '已中断成员 $rest。');
        default:
          transcript.add(TuiRole.system, kTeamUsage);
      }
    } on TeamException catch (e) {
      transcript.add(TuiRole.system, '团队操作失败：${e.message}');
    }
  }

  /// `/task [claim|release <id>]`：任务板手动干预（不经模型）。
  Future<void> _handleTask(String arg) async {
    final AgentTeam? team = _sessionCtx?.get<AgentTeam>('team');
    if (team == null) {
      transcript.add(TuiRole.system, '团队不可用：会话尚未装配团队服务。');
      return;
    }
    final int space = arg.indexOf(' ');
    final String sub = space < 0 ? arg.trim() : arg.substring(0, space).trim();
    final String rest = space < 0 ? '' : arg.substring(space + 1).trim();
    try {
      switch (sub) {
        case 'claim':
          if (rest.isEmpty) {
            transcript.add(TuiRole.system, kTaskUsage);
            return;
          }
          final TeamTask? task = team.task(rest);
          if (task == null) {
            transcript.add(TuiRole.system, '任务不存在：$rest');
            return;
          }
          await team.claimTask(rest, 'user');
          transcript.add(TuiRole.system, '已领取任务：${task.description}');
        case 'release':
          if (rest.isEmpty) {
            transcript.add(TuiRole.system, kTaskUsage);
            return;
          }
          await team.releaseTask(rest, 'user');
          transcript.add(TuiRole.system, '已释放任务 $rest。');
        default:
          transcript.add(TuiRole.system, kTaskUsage);
      }
    } on TeamException catch (e) {
      transcript.add(TuiRole.system, '任务操作失败：${e.message}');
    }
  }

  Future<void> _bind(String id) async {
    final Session session = await _sessions.open(id);
    _session = session;
    final Context ctx = _app.plugin('tui-session:$id', (Context child) {
      provideAgentLoop(child, session: session);
      providePlanMode(child, session: session);
      provideGoal(child, session: session);
      provideSessionSchedule(child, session: session, sessions: _sessions);
      provideScheduleTools(child);
      provideScheduleRuntime(child, deliver: _deliverReminder);
      provideAgentTeam(
        child,
        session: session,
        telemetry: _app.get<Telemetry>('telemetry'),
      );
      provideTeamTools(child);
      configureSession?.call(child, session);
    });
    _sessionCtx = ctx;
    _agent = ctx.agentLoop;
    _planMode = ctx.planMode;
    _goal = ctx.goal;
    // 权限模式按会话恢复：每个会话折叠自己的 permission/mode 后缀，
    // 同时清空审批门的「总是允许」清单（它也是会话级状态）。
    _gate?.resetAlwaysAllowed();
    _permissionMode = restorePermissionMode(session);
    _syncPermissionMode();
    transcript.rebuildFrom(session);
    _eventSub = session.onEvent((SessionEvent event) {
      transcript.apply(event);
      _refresh();
    });
    _bindTeam(ctx);
    ready = true;
  }

  /// 绑定团队订阅与语音播报（装配了团队服务时生效）。
  void _bindTeam(Context ctx) {
    final AgentTeam? team = ctx.get<AgentTeam>('team');
    if (team == null) return;
    _teamSub = TeamSubscription(
      team: team,
      onChanged: (TeamSnapshot _) => _refresh(),
    );
    final TtsService? tts = this.tts;
    if (tts != null) {
      _voice = VoiceReporter(team: team, tts: tts, sink: ttsSink);
    }
  }

  void _unbind() {
    _eventSub?.call();
    _eventSub = null;
    _voice?.dispose();
    _voice = null;
    _approvalGate?.call();
    _approvalGate = null;
    _teamSub?.dispose();
    _teamSub = null;
    _sessionCtx?.dispose();
    _sessionCtx = null;
    _agent = null;
    _planMode = null;
    _goal = null;
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

  /// 已入队、等待轮次收口回报状态的 cron 运行记录 id。
  final Set<String> _cronRuns = <String>{};

  /// cron 交付：空闲时把任务 framing 当作一轮用户输入投递，返回是否成功入队。
  ///
  /// 忙时返回 `false`，cron 运行时不写运行戳，下个 tick 重试；轮次收口时经
  /// [_settleCronRuns] 把执行结果回报给 cron 运行历史。
  Future<bool> deliverCron(String recordId, String framing) async {
    if (busy || _agent == null) return false;
    _cronRuns.add(recordId);
    unawaited(submit(framing));
    return true;
  }

  /// 轮次收口：把本轮结果回报给所有待收口的 cron 运行记录。
  void _settleCronRuns({required bool ok, required String reply}) {
    if (_cronRuns.isEmpty) return;
    final CronRuntime? runtime = _app.get<CronRuntime>('cronRuntime');
    final String excerpt = reply.trim();
    for (final String recordId in _cronRuns.toList()) {
      runtime?.finishRun(recordId,
          ok: ok, excerpt: excerpt.isEmpty ? null : excerpt);
    }
    _cronRuns.clear();
  }

  void _refresh() => onChanged?.call();
}
