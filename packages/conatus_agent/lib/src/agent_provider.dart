/// Agent Loop 的装配：把 [AgentLoop] 接上上下文里已就绪的服务。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'agent_loop.dart';
import 'compaction.dart';
import 'reflection.dart';
import 'router.dart';
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
}) {
  final LlmProvider llm = ctx.require<LlmProvider>('llm');
  final ToolRegistry tools = ctx.require<ToolRegistry>('tools');
  final Telemetry? telemetry = ctx.get<Telemetry>('telemetry');
  final AgentLoop resolved = agent ??
      AgentLoop(
        llm: telemetry == null
            ? llm
            : TelemetryLlmProvider(llm, telemetry: telemetry),
        tools: tools,
        session: session ?? _soleOpenSession(ctx),
        systemPrompt: ctx.get<SystemPrompt>('systemPrompt'),
        compactor: ctx.get<Compactor>('compaction'),
        memory: ctx.get<MemoryStore>('memory'),
        reflector: ctx.get<Reflector>('reflection'),
        router: ctx.get<Router>('router'),
        maxSteps: maxSteps,
        planning: planning,
        onEvent: telemetry == null
            ? null
            : (String type, Map<String, Object?> data) =>
                telemetry.emit(TelemetryEvent(type, data: data)),
      );
  ctx.provide('agentLoop', resolved);
  return resolved;
}

Session? _soleOpenSession(Context ctx) {
  final SessionStore? store = ctx.get<SessionStore>('sessions');
  if (store == null || store.length != 1) return null;
  return store.get(store.ids.single);
}
