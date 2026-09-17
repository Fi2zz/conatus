import 'dart:async';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_team/conatus_team.dart';
import 'package:test/test.dart';

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

ToolContext _ctx(String name, [Map<String, Object?> args = const {}]) =>
    ToolContext(ToolCall(name: name, arguments: args));

void main() {
  test('provideTeamTools 注册 10 个团队工具', () {
    final Context ctx = Context.root();
    final ToolRegistry registry = ToolRegistry();
    ctx.provide('tools', registry);
    final AgentTeamImpl team = AgentTeamImpl(
      leadId: 'lead',
      host: ctx,
      llm: _ScriptedProvider(<LlmResult>[_text('ok')]),
      tools: registry,
    );
    ctx.provide('team', team);
    provideTeamTools(ctx, team: team, tools: registry);
    expect(registry.names, contains('spawn_teammate'));
    expect(registry.names, contains('send_message'));
    expect(registry.names, contains('followup_task'));
    expect(registry.names, contains('list_agents'));
    expect(registry.names, contains('wait_agent'));
    expect(registry.names, contains('interrupt_agent'));
    expect(registry.names, contains('team_task_create'));
    expect(registry.names, contains('team_task_list'));
    expect(registry.names, contains('team_task_get'));
    expect(registry.names, contains('team_task_update'));
    ctx.dispose();
  });

  test('spawn_teammate 工具创建成员', () async {
    final Context ctx = Context.root();
    final ToolRegistry registry = ToolRegistry();
    final AgentTeamImpl team = AgentTeamImpl(
      leadId: 'lead',
      host: ctx,
      llm: _ScriptedProvider(<LlmResult>[_text('ok')]),
      tools: registry,
    );
    final SpawnTeammateTool tool = SpawnTeammateTool(team);
    final ToolResult result = await tool.call(_ctx('spawn_teammate',
        <String, Object?>{'name': 'reviewer'}));
    expect(result.isError, false);
    expect(team.members.length, 1);
    expect(team.members.single.name, 'reviewer');
    ctx.dispose();
  });

  test('team_task_create → list → get → update 链', () async {
    final Context ctx = Context.root();
    final ToolRegistry registry = ToolRegistry();
    final AgentTeamImpl team = AgentTeamImpl(
      leadId: 'lead',
      host: ctx,
      llm: _ScriptedProvider(<LlmResult>[_text('ok')]),
      tools: registry,
    );
    final TeamTaskCreateTool create = TeamTaskCreateTool(team);
    final TeamTaskListTool list = TeamTaskListTool(team);
    final TeamTaskGetTool get = TeamTaskGetTool(team);
    final TeamTaskUpdateTool update = TeamTaskUpdateTool(team);

    final ToolResult created = await create.call(_ctx('team_task_create',
        <String, Object?>{'description': '审查代码', 'assignee': 'm1'}));
    expect(created.isError, false);
    final String taskId = (created.value as Map<String, Object?>)['id']! as String;

    final ToolResult listed = await list.call(_ctx('team_task_list'));
    expect((listed.value as List).length, 1);

    final ToolResult got = await get
        .call(_ctx('team_task_get', <String, Object?>{'task_id': taskId}));
    expect(got.isError, false);

    // 需要先 spawn 成员才能 claim
    await team.spawn(name: 'm1');
    final ToolResult updated = await update.call(_ctx('team_task_update',
        <String, Object?>{
          'task_id': taskId,
          'teammate_id': 'm1',
          'status': 'claimed',
        }));
    expect(updated.isError, false);
    ctx.dispose();
  });
}
