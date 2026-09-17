/// /team 与 /task 斜杠命令测试（不经模型，直调团队服务）。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

/// 按脚本返回结果的假 provider（团队装配需要 llm 服务在场）。
class _ScriptedProvider implements LlmProvider {
  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      const LlmResult(content: 'ok', provider: 'scripted', model: 'm');

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

Future<(ConatusTuiController, Context, AgentTeam)> _build() async {
  final Context app = Context.root();
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider()]));
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    initialSession: 's1',
    modelLabel: 'scripted',
    onExit: () {},
  );
  AgentTeam? team;
  controller.configureSession = (Context ctx, Session session) {
    team = ctx.get<AgentTeam>('team');
  };
  await controller.start();
  return (controller, app, team!);
}

Future<void> _flush() async {
  // 让团队变更事件派发完成，快照先行于命令执行。
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('/team status：无团队时提示无任务', () async {
    final (ConatusTuiController controller, Context app, AgentTeam _) =
        await _build();
    await controller.handleLine('/team status');
    expect(
      controller.transcript.messages.last.text,
      contains('现在没有正在进行的团队任务'),
    );
    app.dispose();
  });

  test('/team status：有成员时输出进度摘要', () async {
    final (ConatusTuiController controller, Context app, AgentTeam team) =
        await _build();
    await team.spawn(name: 'reviewer');
    await _flush();
    await controller.handleLine('/team status');
    expect(
      controller.transcript.messages.last.text,
      contains('0/0 个任务完成'),
    );
    // 空闲成员不进入摘要，但团队已激活（不再是"没有团队任务"）。
    expect(
      controller.transcript.messages.last.text,
      isNot(contains('现在没有正在进行的团队任务')),
    );
    app.dispose();
  });

  test('/task claim：领取成功后 assignee 为 user', () async {
    final (ConatusTuiController controller, Context app, AgentTeam team) =
        await _build();
    final TeamTask task = await team.createTask(description: '审查方案');
    await controller.handleLine('/task claim ${task.id}');
    expect(
      controller.transcript.messages.last.text,
      contains('已领取任务：审查方案'),
    );
    expect(team.task(task.id)!.assigneeId, 'user');
    app.dispose();
  });

  test('/task claim：任务不存在时提示', () async {
    final (ConatusTuiController controller, Context app, AgentTeam _) =
        await _build();
    await controller.handleLine('/task claim nope');
    expect(
      controller.transcript.messages.last.text,
      contains('任务不存在：nope'),
    );
    app.dispose();
  });

  test('/task claim 依赖未完成时捕获 TeamException', () async {
    final (ConatusTuiController controller, Context app, AgentTeam team) =
        await _build();
    final TeamTask dep = await team.createTask(description: '前置');
    final TeamTask task =
        await team.createTask(description: '后续', dependsOn: <String>[dep.id]);
    await controller.handleLine('/task claim ${task.id}');
    expect(
      controller.transcript.messages.last.text,
      contains('任务操作失败'),
    );
    app.dispose();
  });

  test('/task release：释放已领取的任务', () async {
    final (ConatusTuiController controller, Context app, AgentTeam team) =
        await _build();
    final TeamTask task = await team.createTask(description: '审查方案');
    await team.claimTask(task.id, 'user');
    await controller.handleLine('/task release ${task.id}');
    expect(
      controller.transcript.messages.last.text,
      contains('已释放任务 ${task.id}'),
    );
    expect(team.task(task.id)!.status, TeamTaskStatus.pending);
    app.dispose();
  });

  test('/team interrupt：中断真实成员', () async {
    final (ConatusTuiController controller, Context app, AgentTeam team) =
        await _build();
    final Teammate mate = await team.spawn(name: 'reviewer');
    await controller.handleLine('/team interrupt ${mate.id}');
    expect(
      controller.transcript.messages.last.text,
      contains('已中断成员 ${mate.id}'),
    );
    app.dispose();
  });

  test('/team interrupt：成员不存在时报错', () async {
    final (ConatusTuiController controller, Context app, AgentTeam _) =
        await _build();
    await controller.handleLine('/team interrupt ghost');
    expect(
      controller.transcript.messages.last.text,
      contains('团队操作失败'),
    );
    app.dispose();
  });

  test('/team 与 /task 用法提示', () async {
    final (ConatusTuiController controller, Context app, AgentTeam _) =
        await _build();
    await controller.handleLine('/team bogus');
    expect(
      controller.transcript.messages.last.text,
      contains('用法：/team'),
    );
    await controller.handleLine('/task bogus');
    expect(
      controller.transcript.messages.last.text,
      contains('用法：/task'),
    );
    app.dispose();
  });
}
