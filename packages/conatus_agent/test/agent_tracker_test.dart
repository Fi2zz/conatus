/// Agent Loop 的轮次钩子多播契约：多个 tracker 并存、顺序、摘除与失败隔离。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _Provider implements LlmProvider {
  _Provider(this.reply, {this.fail = false});

  final String reply;
  final bool fail;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    if (fail) throw StateError('模型失败');
    return LlmResult(content: reply, provider: 'scripted', model: 'm');
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

/// 记录调用序列；[throwOn] 非空时在该阶段抛错。
class _Recorder implements AgentTurnTracker {
  _Recorder(this.name, {this.log, this.throwOn});

  final String name;
  final List<String>? log;
  final String? throwOn;
  final List<Object?> errors = <Object?>[];

  @override
  Future<void> beginTurn(String userInput) async {
    _record('begin');
  }

  @override
  Future<void> endTurn({Object? result, Object? error}) async {
    errors.add(error);
    _record('end');
  }

  void _record(String phase) {
    log?.add('$name.$phase');
    if (throwOn == phase) throw StateError('$name 在 $phase 抛错');
  }
}

void main() {
  test('两个 tracker 按注册顺序收到 begin/end', () async {
    final List<String> log = <String>[];
    final AgentLoop loop = AgentLoop(
      llm: _Provider('好的'),
      tools: ToolRegistry(),
    );
    addTearDown(loop.addTurnTracker(_Recorder('a', log: log)));
    addTearDown(loop.addTurnTracker(_Recorder('b', log: log)));

    await loop.run('在吗');

    expect(log, <String>['a.begin', 'b.begin', 'a.end', 'b.end']);
  });

  test('撤销后不再收到钩子，且撤销幂等', () async {
    final List<String> log = <String>[];
    final AgentLoop loop = AgentLoop(
      llm: _Provider('好的'),
      tools: ToolRegistry(),
    );
    final Disposer off = loop.addTurnTracker(_Recorder('a', log: log));
    off();
    off();

    await loop.run('在吗');

    expect(log, isEmpty);
  });

  test('一个 tracker 抛错不影响另一个，也不让一轮失败', () async {
    final List<String> log = <String>[];
    final List<TelemetryEvent> events = <TelemetryEvent>[];
    final AgentLoop loop = AgentLoop(
      llm: _Provider('好的'),
      tools: ToolRegistry(),
      onEvent: (String type, Map<String, Object?> data) =>
          events.add(TelemetryEvent(type, data: data)),
    );
    addTearDown(
      loop.addTurnTracker(_Recorder('bad', log: log, throwOn: 'end')),
    );
    addTearDown(loop.addTurnTracker(_Recorder('good', log: log)));

    final AgentTurn turn = await loop.run('在吗');

    expect(turn.reply, '好的');
    expect(log, contains('good.end'));
    expect(
      events.where((TelemetryEvent e) => e.name == 'agent.tracker.failed'),
      hasLength(1),
    );
  });

  test('轮次失败时所有 tracker 收到 endTurn(error)', () async {
    final _Recorder tracker = _Recorder('a');
    final AgentLoop loop = AgentLoop(
      llm: _Provider('x', fail: true),
      tools: ToolRegistry(),
    );
    addTearDown(loop.addTurnTracker(tracker));

    await expectLater(loop.run('在吗'), throwsStateError);

    expect(tracker.errors, hasLength(1));
    expect(tracker.errors.single, isNotNull);
  });
}
