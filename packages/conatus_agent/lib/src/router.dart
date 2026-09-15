/// router 插件：Agent Loop 调模型前的确定性快路径。
///
/// 服务键 `'router'`。给定用户输入，路由先做本地判断：
///
/// * [RouteReply] —— 命中本地直答，直接收口，**不调模型**；
/// * [RouteTools] —— 命中确定性工具，预置工具调用，执行后仍由模型收口；
/// * [RoutePass]  —— 未命中，落回模型决策（默认行为）。
///
/// 未提供 Router 时 Agent Loop 行为与改造前完全一致。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_llm/conatus_llm.dart';

/// 一次路由决策。
sealed class RouteDecision {
  const RouteDecision._();

  /// 本地直答：直接作为回复收口。
  const factory RouteDecision.reply(String text) = RouteReply;

  /// 预置工具调用：先执行，再让模型据此收口。
  const factory RouteDecision.tools(List<LlmToolCall> calls) = RouteTools;

  /// 未命中：落回模型决策。
  const factory RouteDecision.pass() = RoutePass;
}

/// 本地直答决策。
final class RouteReply extends RouteDecision {
  const RouteReply(this.text) : super._();

  /// 直接回复给用户的文本。
  final String text;
}

/// 预置工具调用决策。
final class RouteTools extends RouteDecision {
  const RouteTools(this.calls) : super._();

  /// 预先确定的工具调用（参数已定）。
  final List<LlmToolCall> calls;
}

/// 未命中决策。
final class RoutePass extends RouteDecision {
  const RoutePass() : super._();
}

/// 确定性路由器：命中即走快路径，未命中落模型。
abstract interface class Router {
  /// 对一轮用户输入做路由判断。
  Future<RouteDecision> route(String input);
}

/// `ctx.router`：当前上下文可见的路由器；未提供返回 `null`。
extension RouterContext on Context {
  /// 取当前上下文可见的 [Router]（未提供时返回 `null`）。
  Router? get router => get<Router>('router');
}

/// 将 [Router] 作为 `'router'` 服务提供到上下文。
Router provideRouter(Context ctx, Router router) {
  ctx.provide('router', router);
  return router;
}
