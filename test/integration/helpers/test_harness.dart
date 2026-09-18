/// 集成测试装配器：构建一棵完整的 Context 树，注入所有 Mock 外部 IO，
/// 返回可操作的句柄。所有集成测试共用。
library;

import 'dart:async';
import 'package:conatus/conatus.dart';
import 'package:test/test.dart';

import 'scripted_llm.dart';
import 'terminal_io.dart';

/// 集成测试的装配器。
///
/// 核心装配固定提供：telemetry（内存）、tools、systemPrompt、askUser（终端
/// 替身，输入用 [type] 投递）、approval（经 askUser 询问）、脚本化 llm、
/// agentLoop（绑定 [Session]）。场景需要的额外能力（planMode / goal / team /
/// cron / alerting / browserUse / search / shell）由各场景测试通过 [app]
/// 自行 `provideXxx(...)` 补装。
class TestHarness {
  TestHarness._(
    this.app,
    this.llm,
    this.output,
    this.askUser,
    this.telemetry,
    this.session,
    this.agent,
  );

  static Future<TestHarness> create({
    List<LlmResult>? llmScript,
    int reflectionMaxRetries = 0,
  }) async {
    final Context app = Context.root();
    final InMemoryTelemetry telemetry = InMemoryTelemetry();
    final TerminalOutput output = TerminalOutput();
    final CliAskUser askUser = CliAskUser(sink: output);
    final Session session = Session(id: 'integration');
    final ScriptedLlm llm = ScriptedLlm(llmScript ?? const <LlmResult>[]);

    provideTelemetry(app, telemetry: telemetry);
    provideTools(app);
    provideSystemPrompt(app);
    provideAskUser(app, askUser: askUser);
    provideApproval(app, approval: AskUserApproval(askUser: askUser));
    app.provide('llm', llm);
    // reflection 是 AgentLoop 的构造依赖，必须先于 provideAgentLoop 装配。
    if (reflectionMaxRetries > 0) {
      app.provide(
          'reflection', Reflector(llm: llm, maxRetries: reflectionMaxRetries));
    }
    final AgentLoop agent = provideAgentLoop(app, session: session);

    return TestHarness._(app, llm, output, askUser, telemetry, session, agent);
  }

  /// 完整 Context 树；场景在此补装额外能力。
  final Context app;

  /// 脚本化 LLM（含请求记录）。
  final ScriptedLlm llm;

  /// 终端输出（askUser 的 prompt、告警行等）。
  final TerminalOutput output;

  /// 终端提问器；[type] 通过它投递输入。
  final CliAskUser askUser;

  /// 内存遥测（`recent` 供断言）。
  final InMemoryTelemetry telemetry;

  /// 绑定的会话。
  final Session session;

  /// Agent Loop。
  final AgentLoop agent;

  /// 每轮 Agent 的回复记录。
  final List<String> replies = <String>[];

  /// 最近一轮回复。
  String get lastReply => replies.isEmpty ? '' : replies.last;

  /// 投递一行用户输入（答复正在等待的 askUser 提问）。
  void type(String line) => askUser.submit(line);

  /// 跑一轮 Agent，等待收口，记录回复。
  Future<AgentTurn> run(String userInput) async {
    final AgentTurn turn = await agent.run(userInput);
    replies.add(turn.reply);
    return turn;
  }

  /// 等待异步装配与后台任务收敛（如 browser 工具注册）。
  Future<void> settle({Duration delay = const Duration(milliseconds: 50)}) =>
      Future<void>.delayed(delay);

  /// 轮询直到终端输出包含 [substring]（用于等待 askUser 提问出现）。
  ///
  /// 集成测试里审批发生在 Agent 运行中途：先启动 [agent.run]，再用本方法
  /// 等提问写进输出，然后 [type] 投递答复。
  Future<void> waitForOutput(
    String substring, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final Stopwatch watch = Stopwatch()..start();
    while (!output.text.contains(substring)) {
      if (watch.elapsed > timeout) {
        fail('等待输出超时: $substring\n实际输出:\n${output.text}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// 等待一次**新的** askUser 提问出现（相对调用时已存在的提问数）。
  ///
  /// 同一 prompt 可能被问多次（如两次相同的审批），[waitForOutput] 无法区分，
  /// 用本方法按提问计数等待。
  Future<void> waitForAsk({Duration timeout = const Duration(seconds: 5)}) async {
    final int baseline = output.lines.length;
    final Stopwatch watch = Stopwatch()..start();
    while (output.lines.length <= baseline) {
      if (watch.elapsed > timeout) {
        fail('等待新提问超时（基线 $baseline 行）\n实际输出:\n${output.text}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// 断言 telemetry 出现过指定事件（可选校验 data 子集）。
  void expectEvent(String name, {Map<String, Object?>? data}) {
    final Iterable<TelemetryEvent> matches = telemetry.recent
        .where((TelemetryEvent event) => event.name == name);
    expect(matches, isNotEmpty,
        reason: '未找到事件: $name\n实际事件序列:\n${_eventNames().join('\n')}');
    if (data != null) {
      expect(
        matches.any((TelemetryEvent event) =>
            data.entries.every((MapEntry<String, Object?> kv) =>
                event.data[kv.key] == kv.value)),
        isTrue,
        reason: '事件 $name 的 data 不匹配: $data',
      );
    }
  }

  /// 断言事件按 [names] 顺序先后出现。
  void expectEventOrder(List<String> names) {
    var lastIndex = -1;
    for (final String name in names) {
      final int index =
          telemetry.recent.indexWhere((TelemetryEvent e) => e.name == name);
      expect(index, greaterThan(lastIndex), reason: '$name 顺序错误');
      lastIndex = index;
    }
  }

  /// 断言从未出现指定事件。
  void expectNoEvent(String name) {
    expect(telemetry.recent.where((TelemetryEvent e) => e.name == name), isEmpty,
        reason: '不应出现事件: $name');
  }

  /// 断言最近一轮回复包含 [substring]。
  void expectReplyContains(String substring) {
    expect(
      lastReply.contains(substring),
      isTrue,
      reason: '回复未包含: $substring\n实际回复: $lastReply',
    );
  }

  /// 清理：释放整棵 Context 树。
  Future<void> dispose() async => app.dispose();

  List<String> _eventNames() =>
      telemetry.recent.map((TelemetryEvent e) => e.name).toList();
}
