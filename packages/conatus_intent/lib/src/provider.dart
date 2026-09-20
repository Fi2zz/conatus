/// Intent 插件入口：装配路由器，并（可选）接到 Agent Loop 的确定性快路径。
///
/// 依赖全部可选，缺省时降级：无 `llm` → 只用正则；无 `tools` → 工具动作交给
/// Agent Loop 的既有管线；无 `telemetry` / `sessions` → 不埋点、不记录。
library;

import 'dart:convert';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

import 'action.dart';
import 'embedding/embedding_provider.dart';
import 'intent.dart';
import 'route.dart';
import 'router.dart';
import 'router_impl.dart';

/// `conatus_skill` 的 `skill` 工具名；[DelegateAction] 经它取回技能正文。
const String kSkillLoadToolName = 'skill';

/// `ctx.intentRouter`：当前上下文可见的 [IntentRouter]。
extension IntentContext on Context {
  /// 取当前上下文可见的 [IntentRouter]（未提供时抛 [StateError]）。
  IntentRouter get intentRouter => require<IntentRouter>('intentRouter');
}

/// 把 [IntentRouter] 作为 `'intentRouter'` 服务提供到上下文。
///
/// [fastPath] 为 true（缺省）时，同时把它接到 Agent Loop 的 `'router'` 快路径：
/// 正则或向量命中即按动作类型短路，未命中落回完整 Agent Loop。
///
/// **装配顺序**：Agent Loop 在**构造时**读取 `'router'`，因此必须在
/// `provideAgentLoop` 之前调用本函数，否则快路径不生效。上下文里已经提供了
/// `'router'` 时（例如别处已 `provideRouter`），传 `fastPath: false` 只提供服务。
IntentRouter provideIntentRouter(
  Context ctx, {
  IntentRouter? router,
  EmbeddingProvider? embedder,
  List<Intent>? intents,
  double vectorThreshold = 0.85,
  Telemetry? telemetry,
  Session? session,
  bool fastPath = true,
}) {
  final IntentRouter resolved = router ??
      DefaultIntentRouter(
        embedder: embedder,
        vectorThreshold: vectorThreshold,
        telemetry: telemetry ?? ctx.get<Telemetry>('telemetry'),
        sessionOf: () => session ?? _soleOpenSession(ctx),
      );
  for (final Intent intent in intents ?? const <Intent>[]) {
    resolved.register(intent);
  }
  ctx.onDispose(resolved.dispose);
  ctx.provide('intentRouter', resolved);
  if (fastPath) provideRouter(ctx, IntentRouterAdapter(resolved));
  return resolved;
}

/// 把 [IntentRouter] 接到 Agent Loop 的确定性快路径。
///
/// 命中后按动作类型翻译成 [RouteDecision]：
///
/// * [DirectAction] → [RouteReply]：直接收口，**零模型调用**；
/// * [ToolAction] → [RouteTools]：预置工具调用，执行后由模型收口；
/// * [DelegateAction] → [RouteTools]：先调 `skill` 工具取回技能正文，再由模型收口；
/// * 未命中 → [RoutePass]：行为与没装路由器完全一致。
///
/// 命中信息（意图名 / 来源 / 置信度）经 `IntentRouter.changes`、遥测与
/// `intent/routed` 会话事件外露——快路径本身不产生 `llm/request` 事件。
class IntentRouterAdapter implements Router {
  /// 构造适配器。
  const IntentRouterAdapter(this.router);

  /// 被适配的路由器。
  final IntentRouter router;

  @override
  Future<RouteDecision> route(String input) async {
    final RouteResult result = await router.route(input);
    final Intent? intent = result.intent;
    if (intent == null) return const RoutePass();
    return _decide(intent, RouteContext(input: input));
  }

  Future<RouteDecision> _decide(Intent intent, RouteContext ctx) async {
    final RoutedAction action = intent.action;
    switch (action) {
      case DirectAction():
        return RouteDecision.reply(await _text(action, ctx));
      case ToolAction():
        return _tools(action.tool, intent, action.resolveArgs(ctx));
      case DelegateAction():
        return _tools(kSkillLoadToolName, intent, <String, Object?>{
          'name': action.skill,
        });
    }
  }

  Future<String> _text(DirectAction action, RouteContext ctx) async =>
      (await action.run(ctx))?.toString() ?? '';

  RouteDecision _tools(
    String tool,
    Intent intent,
    Map<String, Object?> args,
  ) =>
      RouteDecision.tools(<LlmToolCall>[
        LlmToolCall(
          id: 'intent:${intent.name}',
          name: tool,
          arguments: jsonEncode(args),
        ),
      ]);
}

Session? _soleOpenSession(Context ctx) {
  final SessionStore? store = ctx.get<SessionStore>('sessions');
  if (store == null || store.length != 1) return null;
  return store.get(store.ids.single);
}
