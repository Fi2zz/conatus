/// 控制器：把 Agent Loop 的事件投射到屏上记录，并处理斜杠命令。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_cron/conatus_cron.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_tasks/conatus_tasks.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

/// 模型调用挂起不返回，直到被放行（模拟对端不响应）。
class _HangingProvider implements LlmProvider {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  String get name => 'hanging';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return const LlmResult(content: '迟到', provider: 'hanging', model: 'm');
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

/// 按脚本返回结果的假 provider。
class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this._replies);

  final List<LlmResult> _replies;
  int _index = 0;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      _replies[_index++];

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

/// 内存版 cron 存储：测试替身，不落盘。
class _MemoryCronStorage implements CronStorage {
  CronStorageSnapshot _tasks = const CronStorageSnapshot();
  List<Map<String, Object?>> _history = <Map<String, Object?>>[];

  @override
  CronStorageSnapshot loadTasks() => _tasks;

  @override
  void saveTasks({
    required List<Map<String, Object?>> tasks,
    required Map<String, CronRunStamp> runStamps,
    required Map<String, bool> overrides,
  }) {
    _tasks = CronStorageSnapshot(
      dynamicTasks: tasks,
      runStamps: runStamps,
      overrides: overrides,
    );
  }

  @override
  List<Map<String, Object?>> loadHistory() => _history;

  @override
  void saveHistory(List<Map<String, Object?>> records) =>
      _history = records;
}

Future<(ConatusTuiController, Context)> _build(
  List<LlmResult> replies, {
  void Function(Context ctx, Session session)? configureSession,
  bool withCron = false,
}) async {
  final Context app = Context.root();
  provideTools(app);
  app.effect(() => app.tools.fn(
        'get_time',
        description: '返回时间',
        handler: (ToolContext ctx) async => ToolResult.success('12:00'),
      ));
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider(replies)]));
  provideMemory(app);
  if (withCron) {
    provideCron(app, storage: _MemoryCronStorage());
  }
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    initialSession: 's1',
    modelLabel: 'scripted',
    onExit: () {},
  );
  controller.configureSession = configureSession;
  await controller.start();
  return (controller, app);
}

void main() {
  test('纯文本回复写入 user + assistant', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      <LlmResult>[
        const LlmResult(content: '你好呀', provider: 'scripted', model: 'm'),
      ],
    );

    await controller.handleLine('在吗');

    final List<TuiRole> roles =
        controller.transcript.messages.map((TuiMessage m) => m.role).toList();
    expect(roles, <TuiRole>[TuiRole.user, TuiRole.assistant]);
    expect(controller.transcript.messages.last.text, '你好呀');
    app.dispose();
  });

  test('工具调用轮：回显工具调用与结果，再收口', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      <LlmResult>[
        const LlmResult(
          content: '',
          provider: 'scripted',
          model: 'm',
          toolCalls: <LlmToolCall>[
            LlmToolCall(id: '1', name: 'get_time'),
          ],
        ),
        const LlmResult(
            content: '现在是 12:00。', provider: 'scripted', model: 'm'),
      ],
    );

    await controller.handleLine('几点？');

    final List<TuiRole> roles =
        controller.transcript.messages.map((TuiMessage m) => m.role).toList();
    expect(
      roles,
      <TuiRole>[TuiRole.user, TuiRole.stage, TuiRole.tool, TuiRole.assistant],
    );
    expect(
      controller.transcript.messages
          .firstWhere((TuiMessage m) => m.role == TuiRole.stage)
          .text,
      contains('get_time'),
    );
    expect(
      controller.transcript.messages
          .firstWhere((TuiMessage m) => m.role == TuiRole.tool)
          .text,
      contains('✓'),
    );
    expect(controller.transcript.messages.last.text, '现在是 12:00。');
    app.dispose();
  });

  test('未知命令给出提示，不进入对话链路', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    await controller.handleLine('/nope');

    expect(controller.transcript.messages.single.role, TuiRole.system);
    expect(controller.transcript.messages.single.text, contains('未知命令'));
    app.dispose();
  });

  test('/tools 列出已注册工具', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    await controller.handleLine('/tools');

    expect(controller.transcript.messages.single.text, contains('get_time'));
    app.dispose();
  });

  test('/plan 切换 Plan Mode 并给出提示', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    await controller.handleLine('/plan');
    expect(controller.transcript.messages.last.text, contains('已进入 Plan Mode'));
    expect(
        controller.transcript.messages.last.text, contains('exit_plan_mode'));

    await controller.handleLine('/plan');
    expect(controller.transcript.messages.last.text, contains('已退出 Plan Mode'));
    app.dispose();
  });

  test('Plan Mode 激活时拦截 medium 工具，退出后放行', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );
    app.effect(() => app.tools.fn(
          'danger',
          description: '有副作用的操作',
          riskLevel: ToolRisk.medium,
          handler: (ToolContext ctx) async => ToolResult.success('done'),
        ));
    Future<ToolResult> callDanger() =>
        app.tools.call(const ToolCall(name: 'danger'));

    expect((await callDanger()).isError, isFalse);

    await controller.handleLine('/plan');
    final ToolResult blocked = await callDanger();
    expect(blocked.isError, isTrue);
    expect(blocked.error!.code, 'PLAN_MODE_BLOCKED');

    await controller.handleLine('/plan');
    expect((await callDanger()).isError, isFalse);
    app.dispose();
  });

  test('/goal 无目标时提示创建，set 后 status 显示状态与轮次', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    await controller.handleLine('/goal');
    expect(controller.transcript.messages.last.text, contains('当前没有目标'));

    await controller.handleLine('/goal set 盯机票');
    expect(controller.transcript.messages.last.text, contains('已创建目标'));

    await controller.handleLine('/goal');
    final String status = controller.transcript.messages.last.text;
    expect(status, contains('盯机票'));
    expect(status, contains('active'));
    expect(status, contains('0 / 256'));
    app.dispose();
  });

  test('/goal set 缺文本或子命令未知时给出用法', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    await controller.handleLine('/goal set');
    expect(controller.transcript.messages.last.text, contains('用法：/goal'));

    await controller.handleLine('/goal nope');
    expect(controller.transcript.messages.last.text, contains('用法：/goal'));
    app.dispose();
  });

  test('/goal 已存在非终态目标时 set 失败提示', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    await controller.handleLine('/goal set A');
    await controller.handleLine('/goal set B');

    expect(
      controller.transcript.messages.last.text,
      contains('目标操作失败'),
    );
    app.dispose();
  });

  test('/goal pause / resume / done / clear 全流程', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    await controller.handleLine('/goal set 盯机票');
    await controller.handleLine('/goal pause');
    expect(controller.transcript.messages.last.text, contains('已暂停'));

    await controller.handleLine('/goal resume');
    expect(controller.transcript.messages.last.text, contains('已恢复'));

    await controller.handleLine('/goal edit 盯明天机票');
    expect(controller.transcript.messages.last.text, contains('目标已更新'));

    await controller.handleLine('/goal done');
    expect(controller.transcript.messages.last.text, contains('目标已完成'));

    await controller.handleLine('/goal clear');
    expect(controller.transcript.messages.last.text, contains('目标已清除'));

    await controller.handleLine('/goal');
    expect(controller.transcript.messages.last.text, contains('当前没有目标'));
    app.dispose();
  });

  test('goal 随会话绑定：切换会话后互不继承，四工具保持注册', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );
    expect(app.tools.get(kCreateGoalToolName), isNotNull);

    await controller.handleLine('/goal set 会话一的目标');
    await controller.handleLine('/session work');

    expect(app.tools.get(kCreateGoalToolName), isNotNull);
    await controller.handleLine('/goal');
    expect(controller.transcript.messages.last.text, contains('当前没有目标'));

    await controller.handleLine('/session s1');
    await controller.handleLine('/goal');
    expect(controller.transcript.messages.last.text, contains('会话一的目标'));
    app.dispose();
  });

  test('目标 active 时对话自动续行直到 complete_goal', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      <LlmResult>[
        const LlmResult(content: '收到', provider: 'scripted', model: 'm'),
        const LlmResult(
          content: '',
          provider: 'scripted',
          model: 'm',
          toolCalls: <LlmToolCall>[
            LlmToolCall(id: '1', name: kCompleteGoalToolName),
          ],
        ),
        const LlmResult(content: '目标完成', provider: 'scripted', model: 'm'),
      ],
    );

    await controller.handleLine('/goal set 盯机票');
    await controller.handleLine('开始');

    final List<TuiMessage> assistants = controller.transcript.messages
        .where((TuiMessage m) => m.role == TuiRole.assistant)
        .toList();
    expect(assistants, hasLength(2));
    expect(assistants.last.text, '目标完成');

    await controller.handleLine('/goal');
    expect(controller.transcript.messages.last.text, contains('completed'));
    app.dispose();
  });

  test('exit_plan_mode 随会话绑定注册，切换会话后保持可用', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    expect(app.tools.get(kExitPlanModeToolName), isNotNull);

    await controller.handleLine('/session work');

    expect(app.tools.get(kExitPlanModeToolName), isNotNull);
    app.dispose();
  });

  test('切换会话：id 变化并写入提示', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    await controller.handleLine('/session work');

    expect(controller.sessionId, 'work');
    expect(
      controller.transcript.messages.last.text,
      contains('已切换到会话 work'),
    );
    app.dispose();
  });

  test('会话 id 校验', () {
    expect(isValidSessionId('work_1'), isTrue);
    expect(isValidSessionId('会话-一'), isTrue);
    expect(isValidSessionId('a b'), isFalse);
    expect(isValidSessionId(''), isFalse);
    expect(isValidSessionId('x' * 65), isFalse);
  });

  test('/remember 直接记住，不经模型', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );
    final MemoryStore memory = app.require<MemoryStore>('memory');

    await controller.handleLine('/remember 用户喜欢京剧');

    expect(controller.transcript.messages.single.text, contains('已记住'));
    expect(memory.entries.single.text, '用户喜欢京剧');
    app.dispose();
  });

  test('/forget 直接遗忘，不经模型', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );
    final MemoryStore memory = app.require<MemoryStore>('memory');
    await memory.remember('用户喜欢京剧');

    await controller.handleLine('/forget 京剧');

    expect(controller.transcript.messages.single.text, contains('已遗忘'));
    expect(memory.length, 0);
    app.dispose();
  });

  test('interrupt 打断在飞轮次：busy 复位且不产回复', () async {
    final _HangingProvider provider = _HangingProvider();
    final Context app = Context.root();
    provideTools(app);
    provideLlm(app, llm: FallbackLlm(<LlmProvider>[provider]));
    final SessionStore sessions = provideSessions(app);
    final ConatusTuiController controller = ConatusTuiController(
      app: app,
      sessions: sessions,
      name: 'test',
      initialSession: 's1',
      modelLabel: 'hanging',
      onExit: () {},
    );
    await controller.start();

    final Future<void> running = controller.handleLine('你好');
    await provider.started.future;
    expect(controller.busy, isTrue);

    controller.interrupt();
    await running;

    expect(controller.busy, isFalse);
    expect(
      controller.transcript.messages.any(
        (TuiMessage m) => m.role == TuiRole.assistant,
      ),
      isFalse,
    );
    expect(controller.transcript.messages.last.text, contains('已打断'));
    provider.release.complete();
    app.dispose();
  });

  test('configureSession 缺省 null：会话绑定正常，钩子不参与', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    expect(controller.configureSession, isNull);
    expect(controller.ready, isTrue);
    await controller.handleLine('/tools');
    expect(controller.transcript.messages.single.text, contains('get_time'));
    app.dispose();
  });

  test('configureSession 随会话绑定回调：agentLoop 可见、tasks 可注入', () async {
    final List<Session> bound = <Session>[];
    TaskCenter? center;
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
      configureSession: (Context ctx, Session session) {
        bound.add(session);
        expect(ctx.has('agentLoop'), isTrue);
        expect(ctx.require<AgentLoop>('agentLoop'), isNotNull);
        center = provideTaskCenter(ctx, session: session);
        provideTaskTracking(ctx);
        expect(ctx.require<TaskCenter>('tasks'), same(center));
        expect(ctx.require<AgentLoop>('agentLoop').turnTracker, isNotNull);
      },
    );

    expect(bound, hasLength(1));
    expect(bound.single.id, 's1');
    expect(center, isNotNull);
    app.dispose();
  });

  test('切会话：旧子上下文释放、tasks 移除，新会话再次回调', () async {
    final List<Session> bound = <Session>[];
    final List<Context> contexts = <Context>[];
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
      configureSession: (Context ctx, Session session) {
        bound.add(session);
        contexts.add(ctx);
        provideTaskCenter(ctx, session: session);
        provideTaskTracking(ctx);
      },
    );

    expect(bound, hasLength(1));
    final Context oldCtx = contexts.single;

    await controller.handleLine('/session work');

    expect(bound, hasLength(2));
    expect(bound.last.id, 'work');
    expect(oldCtx.disposed, isTrue);
    expect(oldCtx.get<TaskCenter>('tasks'), isNull);
    app.dispose();
  });

  test('/cron 未装配 cron 服务时提示不可用', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
    );

    await controller.handleLine('/cron');

    expect(controller.transcript.messages.last.text, contains('定时任务不可用'));
    app.dispose();
  });

  test('/cron 空列表与 add / remove / enable / disable 全流程', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
      withCron: true,
    );
    final CronService cron = app.require<CronService>('cron');

    await controller.handleLine('/cron');
    expect(controller.transcript.messages.last.text, contains('当前没有定时任务'));

    await controller.handleLine('/cron add 每十分钟提醒 every 600');
    expect(controller.transcript.messages.last.text, contains('已添加定时任务'));
    final String id = cron.tasks.single.id;
    expect(cron.tasks.single.prompt, '每十分钟提醒');
    expect(cron.tasks.single.every, 600);
    expect(cron.tasks.single.sessionId, 's1'); // add 绑定当前会话

    await controller.handleLine('/cron');
    expect(controller.transcript.messages.last.text, contains(id));
    expect(controller.transcript.messages.last.text, contains('启用'));
    expect(controller.transcript.messages.last.text, contains('每十分钟提醒'));

    await controller.handleLine('/cron disable $id');
    expect(controller.transcript.messages.last.text, contains('已停用'));
    expect(cron.listTasks().single.enabled, isFalse);

    await controller.handleLine('/cron enable $id');
    expect(controller.transcript.messages.last.text, contains('已启用'));
    expect(cron.listTasks().single.enabled, isTrue);

    await controller.handleLine('/cron remove $id');
    expect(controller.transcript.messages.last.text, contains('已删除'));
    expect(cron.tasks, isEmpty);
    app.dispose();
  });

  test('/cron add 解析多词内容与四种规则', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
      withCron: true,
    );
    final CronService cron = app.require<CronService>('cron');

    await controller.handleLine('/cron add 每天早上九点 提醒站会 daily 09:00');
    expect(cron.tasks.single.prompt, '每天早上九点 提醒站会');
    expect(cron.tasks.single.daily, '09:00');

    await controller.handleLine('/cron add 明早八点发邮件 at 2026-09-18T08:00:00');
    expect(cron.tasks, hasLength(2));
    expect(cron.tasks.last.at, '2026-09-18T08:00:00');

    await controller.handleLine('/cron add 每半小时同步 cron 0,30 * * * *');
    expect(cron.tasks, hasLength(3));
    expect(cron.tasks.last.cron, '0,30 * * * *');
    expect(cron.tasks.last.prompt, '每半小时同步');
    app.dispose();
  });

  test('/cron add 支持中文规则词与间隔单位', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
      withCron: true,
    );
    final CronService cron = app.require<CronService>('cron');

    await controller.handleLine('/cron add 喝水 every 600');
    expect(cron.tasks.single.every, 600);

    await controller.handleLine('/cron add 喝水 every 10分钟');
    expect(cron.tasks, hasLength(2));
    expect(cron.tasks.last.every, 600);

    await controller.handleLine('/cron add 喝水 every 600秒');
    expect(cron.tasks, hasLength(3));
    expect(cron.tasks.last.every, 600);

    await controller.handleLine('/cron add 喝水 every 1小时');
    expect(cron.tasks, hasLength(4));
    expect(cron.tasks.last.every, 3600);

    await controller.handleLine('/cron add 喝水 every 10 分钟');
    expect(cron.tasks, hasLength(5));
    expect(cron.tasks.last.every, 600);

    await controller.handleLine('/cron add 吃药 每天 07:00');
    expect(cron.tasks, hasLength(6));
    expect(cron.tasks.last.daily, '07:00');

    await controller.handleLine('/cron add 吃药 每日 07:00');
    expect(cron.tasks, hasLength(7));
    expect(cron.tasks.last.daily, '07:00');

    await controller.handleLine('/cron add 站会 每周一 09:00');
    expect(cron.tasks, hasLength(8));
    expect(cron.tasks.last.cron, '0 9 * * 1');

    await controller.handleLine('/cron add 站会 每周日 09:00');
    expect(cron.tasks, hasLength(9));
    expect(cron.tasks.last.cron, '0 9 * * 0');

    await controller.handleLine('/cron add 站会 每周一 09');
    expect(controller.transcript.messages.last.text, contains('用法：/cron'));
    app.dispose();
  });

  test('/cron add 参数不足或规则非法时给出用法', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
      withCron: true,
    );
    final CronService cron = app.require<CronService>('cron');

    await controller.handleLine('/cron add');
    expect(controller.transcript.messages.last.text, contains('用法：/cron'));

    await controller.handleLine('/cron add 提醒 every 太快');
    expect(controller.transcript.messages.last.text, contains('用法：/cron'));

    await controller.handleLine('/cron add 提醒 every 5');
    expect(controller.transcript.messages.last.text, contains('定时任务操作失败'));
    expect(cron.tasks, isEmpty);

    await controller.handleLine('/cron nope');
    expect(controller.transcript.messages.last.text, contains('用法：/cron'));
    app.dispose();
  });

  test('/cron history 展示运行记录', () async {
    final (ConatusTuiController controller, Context app) = await _build(
      const <LlmResult>[],
      withCron: true,
    );
    final CronService cron = app.require<CronService>('cron');

    await controller.handleLine('/cron history');
    expect(
        controller.transcript.messages.last.text, contains('尚无定时任务运行记录'));

    cron.addDynamicTask(<String, Object?>{
      'id': 't1',
      'prompt': '报时',
      'every': 60,
    });
    final DateTime now = DateTime.now();
    final CronRecordRef ref = cron.allocateRecordRef(now);
    cron.commitFire(ref: ref, taskId: 't1', slot: now, firedAt: now);
    cron.finishRun(ref.id, ok: true, excerpt: '一切正常');

    await controller.handleLine('/cron history');
    final String text = controller.transcript.messages.last.text;
    expect(text, contains('完成'));
    expect(text, contains('t1'));
    expect(text, contains('一切正常'));
    app.dispose();
  });
}
