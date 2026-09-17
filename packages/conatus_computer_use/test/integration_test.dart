import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_computer_use/conatus_computer_use.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tasks/conatus_tasks.dart';
import 'package:test/test.dart';

import 'support/mock_provider.dart';

void main() {
  group('provideComputerUse', () {
    test('提供服务并注册桌面工具', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final MockComputerUseProvider provider = MockComputerUseProvider();

      final ComputerUseRegistry registry =
          provideComputerUse(ctx, provider: provider);
      await pumpEventQueue();

      expect(ctx.get<ComputerUseRegistry>('computerUse'), registry);
      expect(registry.currentProvider, 'mock');
      expect(provider.initialized, isTrue);
      expect(ctx.tools.names,
          containsAll(<String>['screen_capture', 'mouse_click']));

      final ToolResult result = await ctx.tools
          .call(const ToolCall(name: 'mouse_click', arguments: <String, Object?>{'x': 1}));
      expect(result.isError, isFalse);
    });

    test('approval seam：所有输入操作走审批，只读操作放行', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      provideComputerUse(
        ctx,
        provider: MockComputerUseProvider(),
        approval: AutoApproval(false),
      );
      await pumpEventQueue();

      final ToolResult denied =
          await ctx.tools.call(const ToolCall(name: 'mouse_click'));
      expect(denied.isError, isTrue);
      expect(denied.error?.code, 'APPROVAL_DENIED');

      final ToolResult allowed =
          await ctx.tools.call(const ToolCall(name: 'screen_capture'));
      expect(allowed.isError, isFalse);
    });

    test('taskCenter seam：每次操作追踪为 Task', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final DefaultTaskCenter tasks = DefaultTaskCenter();
      provideComputerUse(
        ctx,
        provider: MockComputerUseProvider(),
        taskCenter: tasks,
      );
      await pumpEventQueue();

      await ctx.tools.call(const ToolCall(name: 'mouse_click'));
      expect(tasks.all, hasLength(1));
      expect(tasks.all.single.kind, TaskKind.custom);
      expect(tasks.all.single.status, TaskStatus.completed);
      expect(tasks.all.single.metadata['tool'], 'mouse_click');
    });

    test('telemetry seam：注册 / 调用事件', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      provideComputerUse(
        ctx,
        provider: MockComputerUseProvider(),
        telemetry: telemetry,
      );
      await pumpEventQueue();

      await ctx.tools.call(const ToolCall(name: 'mouse_click'));
      final Iterable<String> names = telemetry.recent
          .map((TelemetryEvent event) => event.name);
      expect(names, contains('computer.provider.registered'));
      expect(names, contains('computer.action.called'));
      expect(names, contains('computer.action.completed'));
    });

    test('启动失败释放此次尝试的注册，可重试', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final MockComputerUseProvider provider = MockComputerUseProvider()
        ..initializeError = StateError('driver not found');

      final ComputerUseRegistry registry =
          provideComputerUse(ctx, provider: provider);
      await pumpEventQueue();

      expect(registry.currentProvider, isNull, reason: '启动失败释放注册');
      expect(ctx.tools.names, isNot(contains('mouse_click')));

      // 修复后重新装配可成功注册
      provider.initializeError = null;
      final Context ctx2 = Context.root();
      provideTools(ctx2);
      final ComputerUseRegistry registry2 =
          provideComputerUse(ctx2, provider: provider);
      await pumpEventQueue();
      expect(registry2.currentProvider, 'mock');
    });

    test('ctx 释放时 dispose Provider 并释放注册', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final MockComputerUseProvider provider = MockComputerUseProvider();
      final ComputerUseRegistry registry =
          provideComputerUse(ctx, provider: provider);
      await pumpEventQueue();

      ctx.dispose();

      expect(provider.disposed, isTrue);
      expect(registry.currentProvider, isNull);
    });

    test('同一上下文重复装配抛 StateError', () {
      final Context ctx = Context.root();
      provideTools(ctx);
      provideComputerUse(ctx, provider: MockComputerUseProvider());
      expect(
        () => provideComputerUse(ctx,
            provider: MockComputerUseProvider(name: 'b')),
        throwsStateError,
      );
    });
  });

  group('registerDesktopTools（会话日志 seam）', () {
    test('记录 computer/action 事件到触发它的 Session 日志', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final InMemorySessionLog log = InMemorySessionLog();
      final DesktopSession desktop = MockDesktopSession(
          toolNames: const <String>['mouse_click']);
      registerDesktopTools(
        ctx,
        desktop,
        sessionId: 'trigger-session',
        sessionLog: log,
      );

      final ToolResult result = await ctx.tools
          .call(const ToolCall(name: 'mouse_click', callId: 'event-7'));
      expect(result.isError, isFalse);

      final List<SessionEvent> events = await log.read('trigger-session').toList();
      expect(events, hasLength(1));
      expect(events.single.type, 'computer/action');
      expect((events.single.data as Map)['tool'], 'mouse_click');
      expect(events.single.parentEventId, 'event-7');
    });
  });
}
