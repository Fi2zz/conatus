import 'dart:async';
import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.script);

  final List<LlmResult> script;
  final List<List<Map<String, dynamic>>?> toolSchemas =
      <List<Map<String, dynamic>>?>[];

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    toolSchemas.add(tools);
    final int index = toolSchemas.length - 1 < script.length
        ? toolSchemas.length - 1
        : script.length - 1;
    return script[index];
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

class _ThrowingProvider implements LlmProvider {
  @override
  String get name => 'boom';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      throw const LlmException('boom', '模型不可用');

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

class _BlockingProvider implements LlmProvider {
  final Completer<LlmResult> gate = Completer<LlmResult>();
  int calls = 0;

  @override
  String get name => 'blocking';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) {
    calls++;
    if (calls == 1) return gate.future;
    return Future<LlmResult>.value(
      const LlmResult(content: 'late', provider: 'blocking', model: 'm'),
    );
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

class _FakeCompaction implements CompactionEngine {
  int calls = 0;

  @override
  int get keepRecent => 4;

  @override
  String? summaryOf(String sessionId) => null;

  @override
  void forget(String sessionId) {}

  @override
  Future<CompactionResult?> compactIfNeeded(
    Session session,
    Summarizer summarize, {
    int? keepRecent,
  }) async {
    calls++;
    return null;
  }
}

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

LlmResult _call(String id, String name, [String args = '{}']) => LlmResult(
      content: '',
      provider: 'scripted',
      model: 'm',
      toolCalls: <LlmToolCall>[
        LlmToolCall(id: id, name: name, arguments: args)
      ],
    );

ToolRegistry _parentTools() {
  final ToolRegistry tools = ToolRegistry();
  tools.fn(
    'get_time',
    description: '返回当前时间',
    handler: (ToolContext ctx) async => ToolResult.success('12:00'),
  );
  return tools;
}

Set<String> _schemaNames(List<Map<String, dynamic>>? schemas) => <String>{
      for (final Map<String, dynamic> schema
          in schemas ?? const <Map<String, dynamic>>[])
        schema['name'] as String,
    };

void main() {
  group('SpawnAgentTool — 隔离与白名单', () {
    test('显式白名单只暴露指定工具，只回传结论', () async {
      final Context host = Context.root();
      final ToolRegistry parent = _parentTools();
      parent.fn(
        'danger',
        riskLevel: ToolRisk.high,
        handler: (ToolContext ctx) async => ToolResult.success('boom'),
      );
      final _ScriptedProvider provider = _ScriptedProvider(
          <LlmResult>[_call('c1', 'get_time'), _text('结论是 12:00')]);
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: provider,
        tools: parent,
      );

      final ToolResult result = await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{
          'task': '查现在几点',
          'tools': <Object?>['get_time'],
        },
      )));

      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect(value['status'], 'success');
      expect(value['output'], '结论是 12:00');
      expect(value['tool_calls'], <String>['get_time']);
      expect(_schemaNames(provider.toolSchemas.first), <String>{'get_time'});
      host.dispose();
    });

    test('显式白名单同样排除 high 风险与 spawn_agent 自身', () async {
      final Context host = Context.root();
      final ToolRegistry parent = _parentTools();
      parent.fn('danger',
          riskLevel: ToolRisk.high,
          handler: (ToolContext ctx) async => ToolResult.success('boom'));
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('ok')]);
      final SpawnAgentTool spawn =
          SpawnAgentTool(host: host, llm: provider, tools: parent);
      parent.register(spawn);

      await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{
          'task': '随便做点什么',
          'tools': <Object?>['get_time', 'danger', 'spawn_agent'],
        },
      )));

      expect(_schemaNames(provider.toolSchemas.first), <String>{'get_time'});
      host.dispose();
    });

    test('默认白名单排除 high 风险与 spawn_agent 自身', () async {
      final Context host = Context.root();
      final ToolRegistry parent = _parentTools();
      parent.fn('write',
          riskLevel: ToolRisk.medium,
          handler: (ToolContext ctx) async => ToolResult.success(''));
      parent.fn('danger',
          riskLevel: ToolRisk.high,
          handler: (ToolContext ctx) async => ToolResult.success(''));
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('ok')]);
      final SpawnAgentTool spawn =
          SpawnAgentTool(host: host, llm: provider, tools: parent);
      parent.register(spawn);

      await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': '随便做点什么'},
      )));

      expect(_schemaNames(provider.toolSchemas.first),
          <String>{'get_time', 'write'});
      host.dispose();
    });

    test('子 Agent 失败收敛为 status=failed', () async {
      final Context host = Context.root();
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: _ThrowingProvider(),
        tools: _parentTools(),
      );

      final ToolResult result = await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': 'x'},
      )));

      expect((result.value! as Map<String, Object?>)['status'], 'failed');
      host.dispose();
    });

    test('interrupt 取消在途子 Agent，收敛为 failed', () async {
      final Context host = Context.root();
      final _BlockingProvider provider = _BlockingProvider();
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: provider,
        tools: _parentTools(),
        defaultTools: <String>['get_time'],
      );

      final Future<ToolResult> pending = spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': '长时间任务'},
      )));
      await Future<void>.delayed(Duration.zero);
      spawn.interrupt();

      final ToolResult result = await pending;
      expect((result.value! as Map<String, Object?>)['status'], 'failed');
      host.dispose();
    });

    test('宿主释放终止在途子 Agent', () async {
      final Context host = Context.root();
      final ToolRegistry parent = _parentTools();
      final _BlockingProvider provider = _BlockingProvider();
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: provider,
        tools: parent,
        defaultTools: <String>['get_time'],
      );

      final Future<ToolResult> pending = spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': '长时间任务'},
      )));
      await Future<void>.delayed(Duration.zero);
      host.dispose();
      provider.gate.complete(_call('c1', 'get_time'));

      final ToolResult result = await pending;
      expect((result.value! as Map<String, Object?>)['status'], 'failed');
    });
  });

  group('子代理权限模式', () {
    test('readonly：medium 工具被拒，不执行', () async {
      final Context host = Context.root();
      final ToolRegistry parent = _parentTools();
      var writes = 0;
      parent.fn(
        'write',
        riskLevel: ToolRisk.medium,
        handler: (ToolContext ctx) async {
          writes++;
          return ToolResult.success('w');
        },
      );
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_call('c1', 'write'), _text('done')]);
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: provider,
        tools: parent,
        permissionMode: SubAgentPermission.readonly,
      );
      parent.register(spawn);

      final ToolResult result = await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{
          'task': 'x',
          'tools': <Object?>['write'],
        },
      )));

      expect(writes, 0, reason: 'readonly 直接拒绝，不执行');
      expect((result.value! as Map<String, Object?>)['status'], 'success');
      host.dispose();
    });

    test('auto：medium 工具免审批执行，不调用审批', () async {
      final Context host = Context.root();
      final ToolRegistry parent = _parentTools();
      var writes = 0;
      parent.fn(
        'write',
        riskLevel: ToolRisk.medium,
        handler: (ToolContext ctx) async {
          writes++;
          return ToolResult.success('w');
        },
      );
      final AutoApproval gate = AutoApproval(false);
      host.provide('approval', gate);
      instrumentApproval(host, approval: gate, tools: parent, threshold: ToolRisk.low);
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_call('c1', 'write'), _text('done')]);
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: provider,
        tools: parent,
        permissionMode: SubAgentPermission.auto,
      );
      parent.register(spawn);

      await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{
          'task': 'x',
          'tools': <Object?>['write'],
        },
      )));

      expect(writes, 1, reason: 'auto 免审批，直接执行');
      expect(gate.requests, 0, reason: '不应调用宿主审批');
      host.dispose();
    });

    test('ask：每个子工具都过审批，拒绝即不执行', () async {
      final Context host = Context.root();
      final ToolRegistry parent = _parentTools();
      final AutoApproval gate = AutoApproval(false);
      host.provide('approval', gate);
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_call('c1', 'get_time'), _text('done')]);
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: provider,
        tools: parent,
        permissionMode: SubAgentPermission.ask,
      );
      parent.register(spawn);

      await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': 'x'},
      )));

      expect(gate.requests, greaterThan(0), reason: 'ask 模式每个子工具都问');
      host.dispose();
    });

    test('ask 无审批服务（headless）→ 退化为只读而非全拒', () async {
      final Context host = Context.root();
      final ToolRegistry parent = _parentTools();
      var writes = 0;
      var reads = 0;
      parent.fn(
        'write',
        riskLevel: ToolRisk.medium,
        handler: (ToolContext ctx) async {
          writes++;
          return ToolResult.success('w');
        },
      );
      parent.fn(
        'read',
        handler: (ToolContext ctx) async {
          reads++;
          return ToolResult.success('r');
        },
      );
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _call('c1', 'write'),
        _call('c2', 'read'),
        _text('done'),
      ]);
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: provider,
        tools: parent,
        permissionMode: SubAgentPermission.ask,
      );
      parent.register(spawn);

      await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{
          'task': 'x',
          'tools': <Object?>['write', 'read'],
        },
      )));

      expect(writes, 0, reason: '无审批人，写操作拒绝（fail-closed）');
      expect(reads, 1, reason: '只读工具照常执行，而非全拒');
      host.dispose();
    });

    test('解析与收紧：只收紧不放宽', () {
      expect(parseSubAgentPermission('readonly'), SubAgentPermission.readonly);
      expect(parseSubAgentPermission('AUTO'), SubAgentPermission.auto);
      expect(parseSubAgentPermission('nope'), isNull);
      expect(tightenBelow(SubAgentPermission.inherit, 'readonly'),
          SubAgentPermission.readonly);
      expect(tightenBelow(SubAgentPermission.inherit, 'auto'),
          SubAgentPermission.inherit);
      expect(tightenBelow(SubAgentPermission.readonly, 'auto'),
          SubAgentPermission.readonly);
      expect(tightenBelow(SubAgentPermission.readonly, null),
          SubAgentPermission.readonly);
    });
  });

  group('provideSpawnAgent', () {
    test('从上下文取 llm/tools 并注册 spawn_agent', () {
      final Context ctx = Context.root();
      final ToolRegistry tools = _parentTools();
      provideLlm(
        ctx,
        llm: FallbackLlm(<LlmProvider>[
          _ScriptedProvider(<LlmResult>[_text('ok')])
        ]),
      );

      provideSpawnAgent(ctx, tools: tools);

      expect(tools.get('spawn_agent'), isNotNull);
      ctx.dispose();
      expect(tools.get('spawn_agent'), isNull);
    });

    test('从上下文取 compaction 接入子 AgentLoop', () async {
      final Context ctx = Context.root();
      final _FakeCompaction compactor = _FakeCompaction();
      ctx.provide('compaction', compactor);
      final ToolRegistry tools = _parentTools();
      provideLlm(
        ctx,
        llm: FallbackLlm(<LlmProvider>[
          _ScriptedProvider(<LlmResult>[_text('ok')])
        ]),
      );

      final SpawnAgentTool spawn = provideSpawnAgent(ctx, tools: tools);
      await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': 'x'},
      )));

      expect(compactor.calls, greaterThan(0),
          reason: '子 Agent 历史长了要能压缩，不能顶爆模型窗口');
      ctx.dispose();
    });
  });
}
