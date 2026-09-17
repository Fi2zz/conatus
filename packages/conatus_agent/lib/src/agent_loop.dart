/// agent 插件：Agent Loop —— 调模型、跑工具、回填结果，直到收口。
/// 组装 system（[SystemPrompt] + 摘要 + 计划 + [MemoryStore]）→ 调模型（带
/// [ToolRegistry.describe]）→ 执行工具（可经 [Reflector] 反思重试）并回填 → 收口。
library;

import 'dart:async';

import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'agent_cancel.dart';
import 'agent_events.dart';
import 'agent_types.dart';
import 'goal_round_driver.dart';
import 'plan.dart';
import 'reflection.dart';
import 'router.dart';

/// Agent Loop。
class AgentLoop {
  AgentLoop({
    required this.llm,
    required this.tools,
    this.session,
    this.systemPrompt,
    this.compactor,
    this.memory,
    this.reflector,
    this.router,
    this.onEvent,
    this.maxSteps = 8,
    this.memoryLimit = 5,
    this.planning = false,
    this.defaultSystemPrompt = '你是一个可靠的助手。需要外部信息或操作时调用工具；否则直接回答。',
  });

  /// 模型接入。
  final LlmProvider llm;

  /// 工具注册表。
  final ToolRegistry tools;

  /// 绑定的会话；null 表示不落事件（临时对话）。
  final Session? session;

  /// system prompt 注册表；null 时用 [defaultSystemPrompt]。
  final SystemPrompt? systemPrompt;

  /// 历史压缩器；null 表示不压缩。
  final CompactionEngine? compactor;

  /// 长记忆库；null 表示不召回/不记录。
  final MemoryStore? memory;

  /// 工具执行后的自省器；null 表示不反思。
  final Reflector? reflector;

  /// 调模型前的确定性路由器；null 表示不路由（直接落模型）。
  final Router? router;

  /// 每轮的观察口（Observability 埋点）：`agent.round` / `agent.finished`。
  final void Function(String type, Map<String, Object?> data)? onEvent;

  /// 单轮最大模型调用步数。
  final int maxSteps;

  /// 每轮召回的长期记忆条数。
  final int memoryLimit;

  /// 是否在无计划时先跑一次规划轮（需注册 `plan_write`）。
  final bool planning;

  /// 未提供 [systemPrompt] 时的兜底人设。
  final String defaultSystemPrompt;

  /// Goal 续行驱动器；非空时，一轮收口后按其决策自动续行（缺省 null，
  /// 不续行）。由 `provideGoal` 在 `goal` 与 `agentLoop` 齐备时后置挂载。
  GoalRoundDriver? goalDriver;

  int _historyStart = 0;
  bool _needsReplan = false;

  /// 跑一轮：从 [userInput] 到最终文本回复。
  ///
  /// [cancel] 非空时，模型调用、工具执行与路由都与其竞速；取消后本方法以
  /// [AgentCancelled] 结束（结果丢弃，调用方可立即开始新一轮）。
  ///
  /// 若挂载了 [goalDriver]，一轮收口后按其决策自动续行：继续则递增轮次并
  /// 以 [kGoalContinuationPrompt] 再跑一轮，直到等待用户或停止为止。
  Future<AgentTurn> run(String userInput, {AgentCancel? cancel}) async {
    final AgentTurn turn = await _runOnce(userInput, cancel: cancel);
    final GoalRoundDriver? driver = goalDriver;
    if (driver == null) return turn;
    if (session?.closed ?? false) return turn;
    final AgentTurn? next = await driver.advance(cancel: cancel);
    return next ?? turn;
  }

  /// 单轮实现：从 [userInput] 到最终文本回复。
  Future<AgentTurn> _runOnce(String userInput, {AgentCancel? cancel}) async {
    final Session? session = this.session;
    ensureSessionOpen(session);
    session
        ?.append(kUserMessageEvent, data: <String, Object?>{'text': userInput});
    final MemoryStore? memory = this.memory;
    if (memory != null) await memory.load();
    _historyStart = await compactSession(
      session: session,
      compactor: compactor,
      llm: llm,
      historyStart: _historyStart,
    );

    Future<ToolResult> invoke(LlmToolCall call) => _race(
          tools.call(ToolCall(
            name: call.name,
            callId: call.id,
            arguments: parseToolArguments(call.arguments),
          )),
          cancel,
        );

    final List<LlmMessage> messages = <LlmMessage>[
      LlmMessage('system', _systemText(userInput), cacheable: true),
      ...deriveAgentMessages(recentAgentEvents(session, _historyStart)),
    ];
    if (planning && session != null && readPlan(session) == null) {
      await runPlanningPhase(
        llm: llm,
        tools: tools,
        session: session,
        messages: messages,
        systemText: () => _systemText(userInput),
      );
    }
    final List<AgentStep> steps = <AgentStep>[];
    // 确定性快路径：命中本地直答直接收口；命中预置工具先执行再交模型收口；
    // 未命中（或未装配 router）行为与无路由完全一致。
    final Router? router = this.router;
    if (router != null) {
      final RouteDecision routed = await _race(router.route(userInput), cancel);
      switch (routed) {
        case RouteReply(:final String text):
          return _finish(session, messages, steps, text, userInput);
        case RouteTools(:final List<LlmToolCall> calls):
          await _runPrepared(session, messages, steps, calls, invoke);
        case RoutePass():
          break;
      }
    }
    for (int step = 0; step < maxSteps; step++) {
      ensureSessionOpen(session);
      if (_needsReplan && planning && session != null) {
        _needsReplan = false;
        await runPlanningPhase(
          llm: llm,
          tools: tools,
          session: session,
          messages: messages,
          systemText: () => _systemText(userInput),
        );
      }
      final LlmResult result = await _race(
        llm.chat(messages, tools: tools.describe()),
        cancel,
      );
      onEvent?.call('agent.round', <String, Object?>{
        'step': step,
        'toolCalls': result.toolCalls.length,
        'contentLength': result.content.length,
      });
      if (result.toolCalls.isEmpty) {
        return _finish(
            session, messages, steps, result.content.trim(), userInput);
      }
      messages.add(
        LlmMessage('assistant', result.content, toolCalls: result.toolCalls),
      );
      session?.append(kAssistantMessageEvent, data: <String, Object?>{
        'text': result.content,
        'toolCalls': toolCallsToJson(result.toolCalls),
      });
      for (final LlmToolCall call in result.toolCalls) {
        ToolResult outcome = await invoke(call);
        final Reflector? reflector = this.reflector;
        if (reflector != null) {
          outcome = await reflectAndRetry(
            reflector: reflector,
            tools: tools,
            task: userInput,
            call: call,
            initial: outcome,
            invoke: invoke,
            plan: session == null ? null : readPlan(session),
            onReplan: () => _needsReplan = true,
          );
        }
        messages.add(LlmMessage('tool', outcome.content, toolCallId: call.id));
        session?.append(kToolResultEvent, data: <String, Object?>{
          'callId': call.id,
          'name': call.name,
          'content': outcome.content,
          'isError': outcome.isError,
        });
        steps.add(AgentStep(call: call, result: outcome));
      }
    }
    return _finish(
        session, messages, steps, '（已达到最大步数 $maxSteps，未收口）', userInput);
  }

  /// 把 [work] 与取消信号竞速：取消后立即以 [AgentCancelled] 结束，其迟到结果
  /// 被 [Completer] 丢弃（不再向上升级为未处理错误）。[cancel] 为空时原样返回。
  Future<T> _race<T>(Future<T> work, AgentCancel? cancel) {
    if (cancel == null) {
      return work;
    }
    if (cancel.cancelled) {
      return Future<T>.error(const AgentCancelled());
    }
    final Completer<T> completer = Completer<T>();
    work.then<void>(
      (T value) {
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );
    cancel.whenCancelled.then<void>((_) {
      if (!completer.isCompleted) {
        completer.completeError(const AgentCancelled());
      }
    });
    return completer.future;
  }

  /// 执行一组预置工具调用：作为一条 assistant 消息 + 若干 tool 结果写入历史，
  /// 供后续模型调用据此收口（与模型自身下发工具调用的口径一致）。
  Future<void> _runPrepared(
    Session? session,
    List<LlmMessage> messages,
    List<AgentStep> steps,
    List<LlmToolCall> calls,
    Future<ToolResult> Function(LlmToolCall call) invoke,
  ) async {
    messages.add(LlmMessage('assistant', '', toolCalls: calls));
    session?.append(kAssistantMessageEvent, data: <String, Object?>{
      'text': '',
      'toolCalls': toolCallsToJson(calls),
    });
    for (final LlmToolCall call in calls) {
      final ToolResult outcome = await invoke(call);
      messages.add(LlmMessage('tool', outcome.content, toolCallId: call.id));
      session?.append(kToolResultEvent, data: <String, Object?>{
        'callId': call.id,
        'name': call.name,
        'content': outcome.content,
        'isError': outcome.isError,
      });
      steps.add(AgentStep(call: call, result: outcome));
    }
  }

  Future<AgentTurn> _finish(
    Session? session,
    List<LlmMessage> messages,
    List<AgentStep> steps,
    String reply,
    String userInput,
  ) async {
    onEvent?.call('agent.finished', <String, Object?>{
      'replyLength': reply.length,
      'steps': steps.length,
    });
    messages.add(LlmMessage('assistant', reply));
    session?.append(kAssistantMessageEvent,
        data: <String, Object?>{'text': reply});
    final MemoryStore? memory = this.memory;
    if (memory != null && reply.isNotEmpty) {
      await memory.remember(
        '用户：$userInput\n助手：$reply',
        tags: <String>{'conversation'},
      );
    }
    return AgentTurn(reply: reply, steps: steps, messages: messages);
  }

  String _systemText(String userInput) => buildSystemText(
        userInput: userInput,
        defaultSystemPrompt: defaultSystemPrompt,
        systemPrompt: systemPrompt,
        compactor: compactor,
        memory: memory,
        session: session,
        memoryLimit: memoryLimit,
      );
}
