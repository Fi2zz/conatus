/// Agent Loop 的装配：把 [AgentLoop] 接上上下文里已就绪的服务。
library;

import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'agent_loop.dart';
import 'caching.dart';
import 'reflection.dart';
import 'router.dart';
import 'session_log_integration.dart';
import 'session_log_llm.dart';
import 'telemetry.dart';

/// `ctx.agentLoop`：当前上下文可见的 Agent Loop。
extension AgentContext on Context {
  /// 取当前上下文可见的 [AgentLoop]（未提供时抛 [StateError]）。
  AgentLoop get agentLoop => require<AgentLoop>('agentLoop');
}

/// 把 [AgentLoop] 作为 `'agentLoop'` 服务提供到上下文。
///
/// 依赖 `llm` 与 `tools`；`systemPrompt` / `compaction` / `memory` / `sessions`
/// 存在时自动接入。未显式传 [session] 时，若恰好只有一个打开的会话则用它。
AgentLoop provideAgentLoop(
  Context ctx, {
  AgentLoop? agent,
  Session? session,
  int maxSteps = 8,
  bool planning = false,
  void Function(LlmStreamEvent event)? onStream,
}) {
  final LlmProvider llm = ctx.require<LlmProvider>('llm');
  final ToolRegistry tools = ctx.require<ToolRegistry>('tools');
  final Telemetry? telemetry = ctx.get<Telemetry>('telemetry');
  final ContextCache? cache = ctx.get<ContextCache>('contextCache');
  final SessionLogRecorder? recorder =
      ctx.get<SessionLogRecorder>('sessionLogRecorder');
  final Session? target = session ?? _soleOpenSession(ctx);
  final AgentLoop resolved = agent ??
      AgentLoop(
        llm: composeLlm(llm,
            telemetry: telemetry, cache: cache, recorder: recorder),
        tools: tools,
        session: target,
        systemPrompt: ctx.get<SystemPrompt>('systemPrompt'),
        compactor: ctx.get<CompactionEngine>('compaction'),
        memory: ctx.get<MemoryStore>('memory'),
        reflector: ctx.get<Reflector>('reflection'),
        router: ctx.get<Router>('router'),
        maxSteps: maxSteps,
        planning: planning,
        onStream: onStream,
        onEvent: telemetry == null
            ? null
            : (String type, Map<String, Object?> data) =>
                telemetry.emit(TelemetryEvent(type, data: data)),
      );
  if (recorder != null && target != null) {
    ctx.effect(() => recorder.attach(target));
    ctx.effect(() => instrumentSessionLogTools(tools, recorder));
  }
  ctx.provide('agentLoop', resolved);
  return resolved;
}

/// 按当前上下文已提供的能力叠加 [LlmProvider] 装饰器。
///
/// 由外到内：Session Log（记录真正发出的请求与收到的响应）→ 缓存度量（从响应
/// 派生命中，不改请求体）→ 遥测（记录提供方行为）→ 原始提供方。未提供对应
/// 能力时不包装，行为与从前一致。
LlmProvider composeLlm(
  LlmProvider base, {
  Telemetry? telemetry,
  ContextCache? cache,
  SessionLogRecorder? recorder,
}) {
  LlmProvider composed = base;
  if (telemetry != null) {
    composed = TelemetryLlmProvider(composed, telemetry: telemetry);
  }
  if (cache != null) {
    composed = CachingLlmProvider(composed, cache: cache);
  }
  if (recorder != null) {
    composed = SessionLogLlmProvider(composed, recorder: recorder);
  }
  return composed;
}

Session? _soleOpenSession(Context ctx) {
  final SessionStore? store = ctx.get<SessionStore>('sessions');
  if (store == null || store.length != 1) return null;
  return store.get(store.ids.single);
}
