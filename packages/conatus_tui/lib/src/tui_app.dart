/// conatus TUI 的运行时装配：把基础设施、Agent Loop 依赖与会话持久化接好。
///
/// 这是一个独立的 [Context] 根，所有服务都随 [dispose] 一并释放。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_cron/conatus_cron.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_search/conatus_search.dart';
import 'package:conatus_skill/conatus_skill.dart';

import 'ask_user_tool.dart';
import 'system_notifier.dart';
import 'tui_choice.dart';
import 'tui_controller.dart';
import 'tui_permission_gate.dart';

/// conatus TUI 运行时：持有根 [Context] 与已装配的服务。
class ConatusTuiRuntime {
  ConatusTuiRuntime._({
    required this.app,
    required this.sessions,
    required this.tools,
    required this.modelLabel,
  });

  /// 根上下文。
  final Context app;

  /// 会话仓库。
  final SessionStore sessions;

  /// 工具注册表。
  final ToolRegistry tools;

  /// 顶栏展示的模型标签。
  final String modelLabel;

  /// 装配一个默认运行时。
  ///
  /// [sessionDir] / [memoryFile] / cron 任务与运行历史缺省落在 [baseDir]
  /// （默认 `<cwd>/.conatus`）下；[webTools] 为 true 时注册 DuckDuckGo（有
  /// [exaApiKey] 则 Exa 优先）；[skills] 为 true 时从 `.conatus/skills` 等目录
  /// 发现技能，注入目录段并注册 `skill` 工具。
  /// [llm] 缺省用 `FallbackLlm.withDefaults()`（豆包 → DeepSeek）；传入后按注入的
  /// 提供商为准（如 DeepSeek-only 的 Demo）。[modelLabel] 覆盖顶栏模型标签。
  // REASON: 装配入口的参数聚合是既定形态（本参数之前已 7 个），调用方是进程级
  // main，不存在逐层透传问题。
  static Future<ConatusTuiRuntime> create({
    String? sessionDir,
    String? memoryFile,
    String? baseDir,
    String? exaApiKey,
    bool webTools = true,
    bool skills = true,
    FallbackLlm? llm,
    String? modelLabel,
  }) async {
    final Context app = Context.root(name: 'conatus');
    final String resolvedBaseDir =
        baseDir ?? '${Directory.current.path}${Platform.pathSeparator}.conatus';
    final String sep = Platform.pathSeparator;

    // ── 工具：时间 / 回显 / 文件读取 / 联网（可选）──────────────
    provideTools(app, timeout: const Duration(seconds: 30));
    app.effect(() => app.tools.fn(
          'get_time',
          description: '返回当前本地时间（RFC 3339，带时区偏移）',
          handler: (ToolContext ctx) async {
            final DateTime now = DateTime.now();
            return ToolResult.success('${now.toIso8601String()}'
                '${formatClockOffset(now.timeZoneOffset)}');
          },
        ));
    app.effect(() => app.tools.fn(
          'echo',
          description: '回显输入文本',
          params: <ParamSpec>[ParamSpec.string('text', required: true)],
          handler: (ToolContext ctx) async =>
              ToolResult.success(ctx.str('text')),
        ));

    provideTelemetry(app);
    instrumentTools(app);

    provideFileSystemLocal(app);
    provideFsTools(app);
    provideToolResultEviction(app);

    // ── 交互：选项浮层 + 工具审批 ────────────────────────────────
    // 浮层状态挂在根上下文：控制器构造时接上重绘回调，审批与 `ask_user`
    // 共用同一条提问通道。审批中间件不在这里装——它随权限模式在控制器里
    // 挂载 / 卸载（见 ConatusTuiController._syncPermissionMode）。
    final TuiChoicePrompt choice = TuiChoicePrompt();
    app.provide('tuiChoice', choice);
    provideApproval(
      app,
      approval: TuiPermissionGate(
        choice: choice,
        fs: app.get<FileSystem>('fs'),
      ),
      // 拦截阈值随权限模式变化，由控制器按需挂载 / 卸载
      // （见 ConatusTuiController._syncPermissionMode），这里只提供服务。
      instrument: false,
    );
    app.effect(() => app.tools.register(AskUserTool(
          host: () => app.get<TuiUserPromptHost>('tuiController'),
        )));

    if (webTools) {
      provideSearch(app, exaApiKey: exaApiKey);
      provideWebTools(app);
    }

    // ── 模型 / 自省 / 子 Agent ──────────────────────────────────
    provideLlm(app, llm: llm);
    provideReflection(app);
    provideSpawnAgent(
      app,
      defaultTools: <String>['get_time', 'echo', 'read_file'],
    );

    // ── 会话持久化（JSONL）+ 会话仓库 ────────────────────────────
    provideSessionPersistence(
      app,
      persistence: JsonlSessionPersistence(
        dir: sessionDir ?? '$resolvedBaseDir${sep}sessions',
      ),
    );
    final SessionStore sessions = provideSessions(app);

    // ── system prompt / 记忆 / 压缩 / 技能 ──────────────────────
    final SystemPrompt prompt = provideSystemPrompt(app);
    prompt.section(PromptSection(
      name: 'persona',
      text: () => '你是"助手"，一位耐心、务实的助手。需要实时信息或操作时调用工具；否则直接简洁回答。',
    ));
    provideTimePrompt(app);
    provideMemory(
      app,
      backend: JsonMemoryBackend(
        file: File(memoryFile ?? '$resolvedBaseDir${sep}memory.json'),
      ),
    );
    provideMemoryTools(app);
    provideCompaction(app);
    provideSkillLibrary(app);
    if (skills) {
      await provideSkillRegistry(app);
      provideSkillCatalog(app);
      provideSkillTool(app);
      await provideSkillFilesystem(app);
    }

    // ── 恢复：数据库（JSON 后端）+ 快照服务 ────────────────────
    provideDatabase(app, defaultBackend: 'json');
    provideDatabaseJson(app);
    provideRecovery(app);

    // ── cron 定时任务：全局任务表 + 运行历史 + 到点交付 ─────────
    provideCron(
      app,
      storage: JsonCronStorage(
        tasksPath: '$resolvedBaseDir${sep}cron-tasks.json',
        historyPath: '$resolvedBaseDir${sep}cron-history.jsonl',
      ),
    );
    provideCronTools(app);
    provideCronRuntime(
      app,
      deliver: (String recordId, String framing, CronTask task) async {
        final ConatusTuiController? controller =
            app.get<ConatusTuiController>('tuiController');
        if (controller == null) return false;
        return controller.deliverCron(recordId, framing);
      },
      options: CronRuntimeOptions(notifier: systemCronNotifier()),
    );

    return ConatusTuiRuntime._(
      app: app,
      sessions: sessions,
      tools: app.tools,
      modelLabel: modelLabel ?? _modelLabel(),
    );
  }

  /// 构造一个绑定到 [initialSession] 的会话控制器。
  ConatusTuiController createController({
    String initialSession = 'tui',
    required void Function() onExit,
    String name = '默认',
  }) {
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: name,
      initialSession: initialSession,
      modelLabel: modelLabel,
      onExit: onExit,
    );
    return controller;
  }

  /// 结束运行时：等待在途写入落定后释放根上下文。
  Future<void> dispose() async {
    await sessions.flush();
    app.dispose();
  }

  static String _modelLabel() {
    final bool ark = (Platform.environment['ARK_API_KEY'] ?? '').isNotEmpty;
    final bool deepseek =
        (Platform.environment['DEEPSEEK_API_KEY'] ?? '').isNotEmpty;
    if (ark) return 'doubao-seed-1-8-251228';
    if (deepseek) return 'deepseek-flash';
    return '未配置（设置 ARK_API_KEY / DEEPSEEK_API_KEY）';
  }
}
