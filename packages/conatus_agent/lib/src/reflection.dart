/// reflection 插件：工具执行后自省，决定「继续 / 重试 / 重新规划」。
///
/// [Reflector] 用一次独立的 LLM 调用（可传更省的 `options`）评估刚执行的工具
/// 结果，[reflectAndRetry] 在 Agent Loop 的工具回填路径上应用决策：`retry`
/// 重跑该工具（有界）、`replan` 触发重新规划、`continue` 直接回填。
/// 策略可经 [ReflectionStrategy] 或上下文 `'reflectionStrategy'` 配置。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'plan.dart';

/// 反思触发策略。
enum ReflectionStrategy {
  /// 每次工具调用后都反思。
  always,

  /// 只在工具失败时反思（默认）。
  onError,

  /// 只在非只读（`riskLevel != low`）工具后反思。
  onRisk,

  /// 关闭反思。
  never,
}

/// 把字符串解析为策略；无法识别时返回 `null`。
ReflectionStrategy? parseReflectionStrategy(Object? value) {
  if (value is ReflectionStrategy) return value;
  final String name = '$value'.trim().toLowerCase();
  for (final ReflectionStrategy strategy in ReflectionStrategy.values) {
    if (strategy.name.toLowerCase() == name) return strategy;
  }
  return null;
}

/// 反思决策的动作。
enum ReflectionAction { continueRun, retry, replan }

/// 一次反思的结论。
class ReflectionDecision {
  const ReflectionDecision(this.action, [this.reason = '']);

  /// 动作。
  final ReflectionAction action;

  /// 理由（模型给出，可为空）。
  final String reason;

  /// 从模型文本解析决策：优先 JSON 的 `decision`，否则关键词，兜底 `continue`。
  static ReflectionDecision parse(String text) {
    final RegExpMatch? match = RegExp(
      r'"decision"\s*:\s*"?(continue|retry|replan)"?',
      caseSensitive: false,
    ).firstMatch(text);
    final String token = (match?.group(1) ?? text).toLowerCase();
    if (token.contains('retry')) {
      return const ReflectionDecision(ReflectionAction.retry);
    }
    if (token.contains('replan')) {
      return const ReflectionDecision(ReflectionAction.replan);
    }
    return const ReflectionDecision(ReflectionAction.continueRun);
  }

  @override
  String toString() => 'ReflectionDecision(${action.name}, $reason)';
}

/// 反思器：独立 LLM 调用 + 可配置策略。
class Reflector {
  Reflector({
    required this.llm,
    this.strategy = ReflectionStrategy.onError,
    this.options,
    this.maxRetries = 1,
  });

  /// 用于反思的模型（可与主 Agent 不同）。
  final LlmProvider llm;

  /// 触发策略。
  final ReflectionStrategy strategy;

  /// 反思调用传给模型的 `options`（如更省的最大 token）。
  final Map<String, dynamic>? options;

  /// 每条工具调用的最大重试次数。
  final int maxRetries;

  /// 是否应对该工具结果发起反思。
  bool shouldReflect(Tool tool, ToolResult result) => switch (strategy) {
        ReflectionStrategy.never => false,
        ReflectionStrategy.always => true,
        ReflectionStrategy.onError => result.isError,
        ReflectionStrategy.onRisk => tool.riskLevel != ToolRisk.low,
      };

  /// 发起一次反思调用，返回决策。
  Future<ReflectionDecision> reflect({
    required String task,
    required LlmToolCall call,
    required ToolResult result,
    Plan? plan,
  }) async {
    final String prompt = '你是一个任务执行监督者。当前任务：$task\n'
        '当前计划：\n${plan?.summary() ?? '（无）'}\n'
        '刚执行的工具：${call.name}\n'
        '工具返回结果：${_clip(result.content)}\n'
        '结果状态：${result.isError ? '失败' : '成功'}\n\n'
        '请评估并按 JSON 回答：'
        '{"decision":"continue|retry|replan","reason":"简短理由"}\n'
        '- continue：结果符合预期，继续；\n'
        '- retry：结果不符合预期，应重试该工具；\n'
        '- replan：需要调整计划，重新规划。';
    final LlmResult response = await llm.chat(
      <LlmMessage>[LlmMessage('user', prompt)],
      options: options,
    );
    return ReflectionDecision.parse(response.content);
  }

  static String _clip(String text) =>
      text.length <= 800 ? text : '${text.substring(0, 800)}…';
}

/// 在工具回填路径上应用反思：必要时重试该工具，或标记需要重新规划。
///
/// 返回最终采用的结果。重试次数受 [Reflector.maxRetries] 限制。
Future<ToolResult> reflectAndRetry({
  required Reflector reflector,
  required ToolRegistry tools,
  required String task,
  required LlmToolCall call,
  required ToolResult initial,
  required Future<ToolResult> Function(LlmToolCall call) invoke,
  Plan? plan,
  void Function()? onReplan,
}) async {
  ToolResult outcome = initial;
  final Tool? tool = tools.get(call.name);
  if (tool == null) return outcome;
  int retries = 0;
  while (reflector.shouldReflect(tool, outcome) &&
      retries < reflector.maxRetries) {
    final ReflectionDecision decision = await reflector.reflect(
      task: task,
      call: call,
      result: outcome,
      plan: plan,
    );
    if (decision.action == ReflectionAction.retry) {
      retries++;
      outcome = await invoke(call);
      continue;
    }
    if (decision.action == ReflectionAction.replan) onReplan?.call();
    break;
  }
  return outcome;
}

/// 把 [Reflector] 作为 `'reflection'` 服务提供到上下文。
///
/// 策略取 [strategy]，否则取上下文 `'reflectionStrategy'`，再否则 `onError`。
Reflector provideReflection(
  Context ctx, {
  Reflector? reflector,
  LlmProvider? llm,
  ReflectionStrategy? strategy,
  Map<String, dynamic>? options,
  int maxRetries = 1,
}) {
  final ReflectionStrategy resolved = strategy ??
      parseReflectionStrategy(ctx.get<Object>('reflectionStrategy')) ??
      ReflectionStrategy.onError;
  final Reflector instance = reflector ??
      Reflector(
        llm: llm ?? ctx.require<LlmProvider>('llm'),
        strategy: resolved,
        options: options,
        maxRetries: maxRetries,
      );
  ctx.provide('reflection', instance);
  return instance;
}
