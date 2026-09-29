/// 子 Agent 进度事件与独立模型派生。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
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
    final int index = calls < script.length ? calls : script.length - 1;
    calls++;
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

class _FailingProvider implements LlmProvider {
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

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

LlmResult _call(String id, String name) => LlmResult(
      content: '',
      provider: 'scripted',
      model: 'm',
      toolCalls: <LlmToolCall>[LlmToolCall(id: id, name: name)],
    );

ToolRegistry _parentTools() {
  final ToolRegistry tools = ToolRegistry();
  tools.fn(
    'get_time',
    description: '返回当前时间',
    handler: (ToolContext ctx) async => ToolResult.success('12:00'),
  );
  tools.fn(
    'failing',
    description: '总是失败',
    handler: (ToolContext ctx) async => ToolResult.failure('炸了'),
  );
  return tools;
}

void main() {
  group('进度事件', () {
    test('起手 → 工具调用 → 工具返回 → 收口，按序发出', () async {
      final Context host = Context.root();
      addTearDown(host.dispose);
      final List<SubAgentEvent> seen = <SubAgentEvent>[];
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: _ScriptedProvider(<LlmResult>[
          _call('c1', 'get_time'),
          _text('结论'),
        ]),
        tools: _parentTools(),
        defaultTools: <String>['get_time'],
        onProgress: seen.add,
      );

      await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': '查时间'},
      )));

      // 每轮模型返回后都报一次 Round（工具调用那一轮也算），所以是 6 条。
      expect(seen.map((SubAgentEvent e) => e.kind), <String>[
        'started',
        'round',
        'tool-call',
        'tool-done',
        'round',
        'finished',
      ]);
      expect((seen.first as SubAgentStarted).task, '查时间');
      expect((seen[2] as SubAgentToolCall).tool, 'get_time');
      expect((seen[3] as SubAgentToolDone).failed, isFalse);
      expect((seen[4] as SubAgentRound).step, 2);
      expect((seen[5] as SubAgentFinished).status, 'success');
      expect((seen[5] as SubAgentFinished).tools, <String>['get_time']);
    });

    test('工具失败也报到屏上（标 ✗）', () async {
      final Context host = Context.root();
      addTearDown(host.dispose);
      final List<SubAgentEvent> seen = <SubAgentEvent>[];
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: _ScriptedProvider(<LlmResult>[
          _call('c1', 'failing'),
          _text('结论'),
        ]),
        tools: _parentTools(),
        defaultTools: <String>['failing'],
        onProgress: seen.add,
      );

      await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': 'x'},
      )));

      final Iterable<SubAgentToolDone> done =
          seen.whereType<SubAgentToolDone>();
      expect(done, hasLength(1));
      expect(done.single.failed, isTrue);
    });

    // 关键：子 Agent 跑十几秒时，屏上必须有东西动。
    test('委托一开始就发 started（不等它跑完）', () async {
      final Context host = Context.root();
      addTearDown(host.dispose);
      final List<SubAgentEvent> seen = <SubAgentEvent>[];
      final Completer<void> gate = Completer<void>();
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: _GatedProvider(gate, <LlmResult>[_text('ok')]),
        tools: _parentTools(),
        defaultTools: <String>['get_time'],
        onProgress: seen.add,
      );

      final Future<ToolResult> pending = spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': '慢任务'},
      )));
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(1));
      expect(seen.single, isA<SubAgentStarted>());

      gate.complete();
      await pending;
      expect(seen.whereType<SubAgentFinished>(), hasLength(1));
    });

    test('失败路径也发 finished(failed)', () async {
      final Context host = Context.root();
      addTearDown(host.dispose);
      final List<SubAgentEvent> seen = <SubAgentEvent>[];
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: _FailingProvider(),
        tools: _parentTools(),
        onProgress: seen.add,
      );

      await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': 'x'},
      )));

      final SubAgentFinished done = seen.whereType<SubAgentFinished>().single;
      expect(done.status, 'failed');
    });

    test('不传 onProgress 时行为不变（不崩、不发事件）', () async {
      final Context host = Context.root();
      addTearDown(host.dispose);
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: _ScriptedProvider(<LlmResult>[_text('ok')]),
        tools: _parentTools(),
      );

      final ToolResult result = await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': 'x'},
      )));

      expect((result.value! as Map<String, Object?>)['status'], 'success');
    });
  });

  group('childLlm 派生', () {
    test('缺省复用主模型', () async {
      final Context host = Context.root();
      addTearDown(host.dispose);
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('ok')]);
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: provider,
        tools: _parentTools(),
      );

      await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': 'x'},
      )));

      expect(provider.calls, 1);
    });

    // 关键回归：子 Agent 的调用必须走派生实例，否则它那十几轮会把**主**
    // 轮次的预算计数器撞爆。
    test('传了工厂时子 Agent 走派生实例，不动主模型', () async {
      final Context host = Context.root();
      addTearDown(host.dispose);
      final _ScriptedProvider main0 = _ScriptedProvider(<LlmResult>[_text('x')]);
      final _ScriptedProvider child0 = _ScriptedProvider(<LlmResult>[_text('ok')]);
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: main0,
        tools: _parentTools(),
        childLlm: (LlmProvider base) {
          expect(identical(base, main0), isTrue, reason: '工厂收到的是主模型');
          return child0;
        },
      );

      await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': 'x'},
      )));

      expect(child0.calls, 1, reason: '子 Agent 的调用走派生实例');
      expect(main0.calls, 0, reason: '主模型计数器保持干净');
    });

    test('每次委托都拿到全新的派生实例', () async {
      final Context host = Context.root();
      addTearDown(host.dispose);
      final _ScriptedProvider main0 = _ScriptedProvider(<LlmResult>[_text('x')]);
      final List<LlmProvider> derived = <LlmProvider>[];
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: main0,
        tools: _parentTools(),
        childLlm: (LlmProvider base) {
          final LlmProvider child =
              _ScriptedProvider(<LlmResult>[_text('ok')]);
          derived.add(child);
          return child;
        },
      );

      for (int i = 0; i < 2; i++) {
        await spawn.call(const ToolContext(ToolCall(
          name: 'spawn_agent',
          arguments: <String, Object?>{'task': 'x'},
        )));
      }

      expect(derived, hasLength(2));
      expect(identical(derived[0], derived[1]), isFalse,
          reason: '预算计数器是有状态的，实例必须每次新建');
    });  });

  group('buildChildRegistry', () {
    test('按白名单取工具并包上代理', () async {
      final ToolRegistry parent = _parentTools();
      final List<SubAgentEvent> seen = <SubAgentEvent>[];

      final ToolRegistry child = buildChildRegistry(
        parent,
        const <String>{'get_time'},
        reporter: seen.add,
      );
      await child.call(const ToolCall(name: 'get_time'));
      expect(child.names, <String>{'get_time'});
      expect(seen.whereType<SubAgentToolCall>().single.tool, 'get_time');
      expect(seen.whereType<SubAgentToolDone>().single.failed, isFalse);
    });

    test('白名单里的未知工具被跳过（不抛）', () {
      final ToolRegistry child =
          buildChildRegistry(_parentTools(), <String>{'nope'});
      expect(child.names, isEmpty);
    });

    test('代理透传 name / description / riskLevel', () {
      final ToolRegistry parent = ToolRegistry();
      parent.fn(
        'risky',
        riskLevel: ToolRisk.medium,
        description: '说明',
        handler: (ToolContext ctx) async => ToolResult.success(''),
      );
      final ToolRegistry child =
          buildChildRegistry(parent, <String>{'risky'}, reporter: (_) {});

      final Tool proxied = child.get('risky')!;
      expect(proxied, isA<ProgressTool>());
      expect(proxied.name, 'risky');
      expect(proxied.description, '说明');
      expect(proxied.riskLevel, ToolRisk.medium);
    });
  });
}

/// 首轮挂起、放闸后才继续的 provider。
class _GatedProvider implements LlmProvider {
  _GatedProvider(this.gate, this.script);

  final Completer<void> gate;
  final List<LlmResult> script;

  @override
  String get name => 'gated';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    await gate.future;
    return script.first;
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
