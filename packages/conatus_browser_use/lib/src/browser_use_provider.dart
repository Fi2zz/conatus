/// browser use 装配：提供 `'browserUse'` 服务，绑定 Session 生命周期。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tasks/conatus_tasks.dart';

import 'browser_action_tool.dart';
import 'provider.dart';
import 'providers/playwright_mcp.dart';
import 'registry.dart';
import 'session_browser.dart';

/// 提供 `'browserUse'` 服务。
///
/// 依赖（全部可选，缺省时降级）：
/// - [provider]：浏览器 Provider；缺省 [PlaywrightMcpProvider]（用 [config]）；
/// - [session]：浏览器绑定 Session（提供时立即初始化并注册工具，
///   Session 关闭时释放浏览器）；fork / 新 Session 用 [initializeBrowserFor]；
/// - [tools]：注册浏览器工具；缺省 `ctx.tools`；
/// - [taskCenter]：浏览器操作作为 Task；缺省 `ctx.get('tasks')`；
/// - [approval]：高危操作审批；显式提供时挂标准审批中间件（threshold high），
///   缺省不挂（自动批准）——注意若调用方已 `provideApproval`，工具的风险等级
///   声明已生效，无需重复传；
/// - [telemetry]：埋点；缺省 `ctx.get('telemetry')`。
///
/// Provider 注册是唯一的：本函数装配时预留槽位；第二个注册（含同名）失败。
/// 返回的注册表随 [ctx] 释放自动释放，同时调用 [BrowserUseProvider.dispose]。
BrowserUseRegistry provideBrowserUse(
  Context ctx, {
  BrowserUseProvider? provider,
  BrowserConfig config = const BrowserConfig(),
  Session? session,
  ToolRegistry? tools,
  TaskCenter? taskCenter,
  Approval? approval,
  Telemetry? telemetry,
}) {
  final BrowserUseProvider resolved =
      provider ?? PlaywrightMcpProvider(config: config);
  final ToolRegistry registry = tools ?? ctx.tools;
  final TaskCenter? tasks = taskCenter ?? ctx.get<TaskCenter>('tasks');
  final Telemetry? sink = telemetry ?? ctx.get<Telemetry>('telemetry');

  final BrowserUseRegistryImpl service = BrowserUseRegistryImpl(resolved);
  final Disposer release = service.claim(resolved.name);
  ctx.provide('browserUse', service);
  ctx.onDispose(() {
    release();
    unawaited(resolved.dispose());
  });
  sink?.emit(TelemetryEvent('browser.provider.registered',
      data: <String, Object?>{'provider': resolved.name}));

  if (approval != null) {
    instrumentApproval(ctx, approval: approval, tools: registry);
  }

  if (session != null) {
    unawaited(attachBrowserSession(
      ctx,
      resolved,
      registry,
      session,
      taskCenter: tasks,
      telemetry: sink,
    ).then<void>((_) {}, onError: (Object _) {}));
  }
  return service;
}

/// 为新 Session（含 fork 结果）初始化**全新浏览器**并注册其工具。
///
/// 浏览器 profile 与登录状态不从 Session 日志恢复（handoff-9 6.2 fork 语义）。
/// 若 [provider] 缺省，从 `'browserUse'` 服务（须 [provideBrowserUse] 装配）
/// 解析已注册的 Provider。初始化失败向上传播。
Future<SessionBrowser> initializeBrowserFor(
  Context ctx,
  Session session, {
  BrowserUseProvider? provider,
  ToolRegistry? tools,
  TaskCenter? taskCenter,
  Telemetry? telemetry,
}) async {
  final BrowserUseProvider resolved = provider ?? _providerOf(ctx);
  final ToolRegistry registry = tools ?? ctx.tools;
  final TaskCenter? tasks = taskCenter ?? ctx.get<TaskCenter>('tasks');
  final Telemetry? sink = telemetry ?? ctx.get<Telemetry>('telemetry');
  return attachBrowserSession(
    ctx,
    resolved,
    registry,
    session,
    taskCenter: tasks,
    telemetry: sink,
  );
}

/// 为 [session] 初始化浏览器、注册全部工具，并绑定关闭释放。
///
/// 工具注册随 Session 关闭一并撤销（同名工具才可被后续 Session 重新注册；
/// 同一时刻仅一个 Session 持有浏览器——handoff-9 4.2 语义）。
/// 初始化失败时向上传播（[provideBrowserUse] 内部会吞掉异步失败，
/// [initializeBrowserFor] 直接暴露给调用方）。
Future<SessionBrowser> attachBrowserSession(
  Context ctx,
  BrowserUseProvider provider,
  ToolRegistry tools,
  Session session, {
  TaskCenter? taskCenter,
  Telemetry? telemetry,
}) async {
  final SessionBrowser browser = await provider.initializeFor(session);
  telemetry?.emit(TelemetryEvent('browser.session.initialized',
      data: <String, Object?>{
        'session': session.id,
        'provider': provider.name,
      }));
  final List<Disposer> toolDisposers = <Disposer>[];
  for (final String name in browser.toolNames) {
    toolDisposers.add(ctx.effect(() => tools.register(BrowserActionTool(
          browser,
          name,
          session: session,
          taskCenter: taskCenter,
          telemetry: telemetry,
        ))));
  }
  session.onClose(() {
    for (final Disposer disposer in toolDisposers) {
      disposer();
    }
    unawaited(_releaseBrowser(provider, session, telemetry));
  });
  return browser;
}

Future<void> _releaseBrowser(
  BrowserUseProvider provider,
  Session session,
  Telemetry? telemetry,
) async {
  await provider.release(session);
  telemetry?.emit(TelemetryEvent('browser.session.released',
      data: <String, Object?>{'session': session.id}));
}

BrowserUseProvider _providerOf(Context ctx) {
  final BrowserUseRegistry service = ctx.require<BrowserUseRegistry>('browserUse');
  final BrowserUseRegistryImpl impl = service is BrowserUseRegistryImpl
      ? service
      : throw StateError('browserUse 服务无法解析 Provider（非默认实现）');
  final BrowserUseProvider? provider = impl.provider;
  if (provider == null) {
    throw StateError('browserUse 服务未绑定 Provider，请先 provideBrowserUse');
  }
  return provider;
}
