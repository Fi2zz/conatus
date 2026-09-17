import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_browser_use/conatus_browser_use.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tasks/conatus_tasks.dart';
import 'package:test/test.dart';

import 'support/mock_provider.dart';

void main() {
  group('provideBrowserUse', () {
    test('提供服务并注册浏览器工具', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final MockBrowserUseProvider provider = MockBrowserUseProvider();
      final Session session = Session(id: 's1');

      final BrowserUseRegistry registry = provideBrowserUse(
        ctx,
        provider: provider,
        session: session,
      );
      await pumpEventQueue();

      expect(ctx.get<BrowserUseRegistry>('browserUse'), registry);
      expect(registry.currentProvider, 'mock');
      expect(provider.initialized, contains(session));
      expect(ctx.tools.names,
          containsAll(<String>['browser_navigate', 'browser_click']));

      final ToolResult result = await ctx.tools
          .call(const ToolCall(name: 'browser_navigate', arguments: <String, Object?>{
        'url': 'https://example.com',
      }));
      expect(result.isError, isFalse);
    });

    test('同一 Session 跨轮次复用浏览器，工具调用不重建客户端', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final MockBrowserUseProvider provider = MockBrowserUseProvider();
      provideBrowserUse(ctx, provider: provider, session: Session(id: 's1'));
      await pumpEventQueue();

      await ctx.tools.call(const ToolCall(name: 'browser_navigate'));
      await ctx.tools.call(const ToolCall(name: 'browser_click'));
      expect(provider.initialized, hasLength(1));
    });

    test('taskCenter seam：每次操作追踪为 Task', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final DefaultTaskCenter tasks = DefaultTaskCenter();
      provideBrowserUse(
        ctx,
        provider: MockBrowserUseProvider(),
        session: Session(id: 's1'),
        taskCenter: tasks,
      );
      await pumpEventQueue();

      await ctx.tools.call(const ToolCall(name: 'browser_navigate'));
      expect(tasks.all, hasLength(1));
      expect(tasks.all.single.kind, TaskKind.custom);
      expect(tasks.all.single.status, TaskStatus.completed);
      expect(tasks.all.single.metadata['tool'], 'browser_navigate');
    });

    test('approval seam：高危工具被拒绝', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final MockBrowserUseProvider provider = MockBrowserUseProvider();
      provider.onInitialize = (Session session) async => MockSessionBrowser(
            sessionId: session.id,
            toolNames: const <String>['browser_evaluate'],
          );
      provideBrowserUse(
        ctx,
        provider: provider,
        session: Session(id: 's1'),
        approval: AutoApproval(false),
      );
      await pumpEventQueue();

      final ToolResult result =
          await ctx.tools.call(const ToolCall(name: 'browser_evaluate'));
      expect(result.isError, isTrue);
      expect(result.error?.code, 'APPROVAL_DENIED');
    });

    test('approval seam：批准后高危工具放行', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final MockBrowserUseProvider provider = MockBrowserUseProvider();
      provider.onInitialize = (Session session) async => MockSessionBrowser(
            sessionId: session.id,
            toolNames: const <String>['browser_evaluate'],
          );
      provideBrowserUse(
        ctx,
        provider: provider,
        session: Session(id: 's1'),
        approval: AutoApproval(true),
      );
      await pumpEventQueue();

      final ToolResult result =
          await ctx.tools.call(const ToolCall(name: 'browser_evaluate'));
      expect(result.isError, isFalse);
    });

    test('session log：操作记录为 browser/action 事件并串 parentEventId',
        () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final Session session = Session(id: 's1');
      provideBrowserUse(
        ctx,
        provider: MockBrowserUseProvider(),
        session: session,
      );
      await pumpEventQueue();

      await ctx.tools.call(const ToolCall(
        name: 'browser_navigate',
        callId: 'event-42',
        arguments: <String, Object?>{'url': 'https://example.com'},
      ));
      final SessionEvent? action = session.events.lastOrNullWhere(
          (SessionEvent event) => event.type == 'browser/action');
      expect(action, isNotNull);
      expect((action!.data as Map)['tool'], 'browser_navigate');
      expect(action.parentEventId, 'event-42');
    });

    test('telemetry seam：注册 / 初始化 / 调用事件', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      provideBrowserUse(
        ctx,
        provider: MockBrowserUseProvider(),
        session: Session(id: 's1'),
        telemetry: telemetry,
      );
      await pumpEventQueue();

      await ctx.tools.call(const ToolCall(name: 'browser_navigate'));
      final Iterable<String> names = telemetry.recent
          .map((TelemetryEvent event) => event.name);
      expect(names, contains('browser.provider.registered'));
      expect(names, contains('browser.session.initialized'));
      expect(names, contains('browser.action.called'));
      expect(names, contains('browser.action.completed'));
    });

    test('Session 关闭时释放浏览器并撤销工具注册', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final MockBrowserUseProvider provider = MockBrowserUseProvider();
      final Session session = Session(id: 's1');
      provideBrowserUse(ctx, provider: provider, session: session);
      await pumpEventQueue();

      session.close();
      await pumpEventQueue();

      expect(provider.released, contains(session));
      expect(ctx.tools.names, isNot(contains('browser_navigate')));
    });

    test('ctx 释放时 dispose Provider 并释放注册', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final MockBrowserUseProvider provider = MockBrowserUseProvider();
      final BrowserUseRegistry registry = provideBrowserUse(
        ctx,
        provider: provider,
      );
      await pumpEventQueue();

      ctx.dispose();

      expect(provider.disposed, isTrue);
      expect(registry.currentProvider, isNull);
    });

    test('同一上下文重复装配抛 StateError', () {
      final Context ctx = Context.root();
      provideTools(ctx);
      provideBrowserUse(ctx, provider: MockBrowserUseProvider());
      expect(
        () => provideBrowserUse(ctx, provider: MockBrowserUseProvider(name: 'b')),
        throwsStateError,
      );
    });
  });
}

extension on List<SessionEvent> {
  SessionEvent? lastOrNullWhere(bool Function(SessionEvent) test) {
    for (final SessionEvent event in reversed) {
      if (test(event)) return event;
    }
    return null;
  }
}
