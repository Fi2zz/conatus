import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_tasks/conatus_tasks.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:test/test.dart';

import '../example/task_center_tracker.dart';

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.script);
  final List<LlmResult> script;
  int calls = 0;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    final int i = calls;
    calls++;
    return script[i < script.length ? i : script.length - 1];
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

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

void main() {
  group('TaskCenterTeamTracker', () {
    test('beginMember 创建 running 的 subAgent 任务', () async {
      final DefaultTaskCenter tasks = DefaultTaskCenter();
      final TaskCenterTeamTracker tracker = TaskCenterTeamTracker(tasks);
      final String? taskId = await tracker.beginMember(
        teammateId: 'm1',
        name: 'reviewer',
        leadId: 'lead',
      );
      expect(taskId, isNotNull);
      final Task task = tasks.get(taskId!)!;
      expect(task.kind, TaskKind.subAgent);
      expect(task.status, TaskStatus.running);
      expect(task.metadata['teammateId'], 'm1');
      expect(task.description, contains('reviewer'));
      tasks.dispose();
    });

    test('completeMember 落 completed 并带 result', () async {
      final DefaultTaskCenter tasks = DefaultTaskCenter();
      final TaskCenterTeamTracker tracker = TaskCenterTeamTracker(tasks);
      final String? taskId =
          await tracker.beginMember(teammateId: 'm1', name: 'a', leadId: 'l');
      await tracker.completeMember('m1', result: '结论');
      final Task task = tasks.get(taskId!)!;
      expect(task.status, TaskStatus.completed);
      expect(task.result, '结论');
      tasks.dispose();
    });

    test('failMember 落 failed 并带 error', () async {
      final DefaultTaskCenter tasks = DefaultTaskCenter();
      final TaskCenterTeamTracker tracker = TaskCenterTeamTracker(tasks);
      final String? taskId =
          await tracker.beginMember(teammateId: 'm1', name: 'a', leadId: 'l');
      await tracker.failMember('m1', error: 'boom');
      final Task task = tasks.get(taskId!)!;
      expect(task.status, TaskStatus.failed);
      expect(task.error, 'boom');
      tasks.dispose();
    });

    test('重复 settle 幂等（already-terminal 不抛）', () async {
      final DefaultTaskCenter tasks = DefaultTaskCenter();
      final TaskCenterTeamTracker tracker = TaskCenterTeamTracker(tasks);
      await tracker.beginMember(teammateId: 'm1', name: 'a', leadId: 'l');
      await tracker.completeMember('m1');
      // 映射已移除：第二次直接静默
      await expectLater(tracker.completeMember('m1'), completes);
      tasks.dispose();
    });

    test('未知 teammateId settle 静默', () async {
      final DefaultTaskCenter tasks = DefaultTaskCenter();
      final TaskCenterTeamTracker tracker = TaskCenterTeamTracker(tasks);
      await expectLater(tracker.completeMember('ghost'), completes);
      expect(tasks.all, isEmpty);
      tasks.dispose();
    });
  });

  group('端到端：AgentTeam + TaskCenter', () {
    test('spawn → 任务树出现 running subAgent；remove → completed', () async {
      final DefaultTaskCenter tasks = DefaultTaskCenter();
      final Context ctx = Context.root();
      final AgentTeamImpl team = AgentTeamImpl(
        leadId: 'lead',
        host: ctx,
        llm: _ScriptedProvider(<LlmResult>[_text('ok')]),
        tools: ToolRegistry(),
        hooks: TeamHooks(taskTracker: TaskCenterTeamTracker(tasks)),
      );
      final Teammate m = await team.spawn(name: 'reviewer');
      final List<Task> active = tasks.active;
      expect(active.length, 1);
      expect(active.single.kind, TaskKind.subAgent);
      expect(active.single.status, TaskStatus.running);

      await team.remove(m.id);
      expect(tasks.get(active.single.id)!.status, TaskStatus.completed);
      team.dispose();
      tasks.dispose();
      ctx.dispose();
    });
  });
}
