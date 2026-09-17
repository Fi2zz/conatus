import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _EchoTool extends Tool {
  const _EchoTool({required this.name, this.riskLevel = ToolRisk.low});

  @override
  final String name;

  @override
  final ToolRisk riskLevel;

  @override
  String get description => '测试工具';

  @override
  Future<ToolResult> call(ToolContext ctx) async => ToolResult.success('ok');
}

List<SessionEvent> _modeEvents(Session session) =>
    session.events.where((SessionEvent e) => e.type == kPlanModeEvent).toList();

void main() {
  group('PlanMode 状态机', () {
    test('enter/exit 转换并通过 changes 广播', () async {
      final SystemPrompt prompt = SystemPrompt();
      final DefaultPlanMode mode = DefaultPlanMode(prompt: prompt);
      final List<PlanModeState> states = <PlanModeState>[];
      final StreamSubscription<PlanModeState> sub =
          mode.changes.listen(states.add);

      mode.enter();
      expect(mode.state, PlanModeState.active);
      expect(prompt.sections.map((PromptSection s) => s.name),
          <String>['plan:policy']);
      expect(prompt.sections.single.order, 100);

      mode.exit();
      expect(mode.state, PlanModeState.inactive);
      expect(prompt.sections, isEmpty);
      // 广播流默认异步投递，断言前冲刷微任务队列。
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(states, <PlanModeState>[
        PlanModeState.active,
        PlanModeState.inactive,
      ]);
    });

    test('enter 幂等；dispose 激活时自动 exit 且整体幂等', () {
      final Session session = Session(id: 's1');
      final SystemPrompt prompt = SystemPrompt();
      final DefaultPlanMode mode =
          DefaultPlanMode(session: session, prompt: prompt);

      mode.enter();
      mode.enter();
      expect(_modeEvents(session), hasLength(1));

      mode.dispose();
      mode.dispose();
      expect(mode.state, PlanModeState.inactive);
      expect(prompt.sections, isEmpty);
      expect(_modeEvents(session), hasLength(2));
      expect(_modeEvents(session).last.data,
          isNot(containsPair('state', 'active')));
    });
  });

  group('session 持久化与恢复', () {
    test('restorePlanModeState 折叠最后一条 plan/mode 事件', () {
      final Session session = Session(id: 's1');
      expect(restorePlanModeState(session), PlanModeState.inactive);

      session
          .append(kPlanModeEvent, data: <String, Object?>{'state': 'active'});
      expect(restorePlanModeState(session), PlanModeState.active);

      session
          .append(kPlanModeEvent, data: <String, Object?>{'state': 'inactive'});
      expect(restorePlanModeState(session), PlanModeState.inactive);
    });

    test('fork 出的会话不继承 Plan Mode 状态', () {
      final Session parent = Session(id: 'p')
        ..append(kPlanModeEvent, data: <String, Object?>{'state': 'active'});
      final Session child = parent.fork();

      expect(restorePlanModeState(parent), PlanModeState.active);
      expect(restorePlanModeState(child), PlanModeState.inactive);
    });

    test('构造时恢复 active 并注册 plan:policy 段，不重复写事件', () {
      final Session session = Session(id: 's1')
        ..append(kPlanModeEvent, data: <String, Object?>{'state': 'active'});
      final SystemPrompt prompt = SystemPrompt();

      final DefaultPlanMode mode =
          DefaultPlanMode(session: session, prompt: prompt);

      expect(mode.state, PlanModeState.active);
      expect(prompt.sections.map((PromptSection s) => s.name),
          <String>['plan:policy']);
      expect(_modeEvents(session), hasLength(1));
    });
  });

  group('approval 集成', () {
    test('AutoApproval(true) 批准', () async {
      final AutoApproval approval = AutoApproval(true);
      final DefaultPlanMode mode = DefaultPlanMode(approval: approval);

      final bool approved = await mode.submitPlan(const Plan(goal: '安排周六'));

      expect(approved, isTrue);
      expect(approval.requests, 1);
    });

    test('AutoApproval(false) 拒绝', () async {
      final DefaultPlanMode mode =
          DefaultPlanMode(approval: AutoApproval(false));

      final bool approved = await mode.submitPlan(const Plan(goal: '安排周六'));

      expect(approved, isFalse);
    });

    test('未提供 approval 时自动批准', () async {
      final DefaultPlanMode mode = DefaultPlanMode();

      expect(await mode.submitPlan(const Plan(goal: 'g')), isTrue);
    });
  });

  group('拦截协同', () {
    test('激活时 medium 工具 PLAN_MODE_BLOCKED；low 与 inactive 放行', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      ctx.tools
        ..register(const _EchoTool(name: 'read_thing'))
        ..register(
            const _EchoTool(name: 'mut_thing', riskLevel: ToolRisk.medium));
      final PlanMode mode = providePlanMode(ctx);

      Future<ToolResult> callMut() =>
          ctx.tools.call(const ToolCall(name: 'mut_thing'));

      // 未激活：放行。
      expect((await callMut()).isError, isFalse);

      mode.enter();
      final ToolResult blocked = await callMut();
      expect(blocked.isError, isTrue);
      expect(blocked.error!.code, 'PLAN_MODE_BLOCKED');
      // 策略允许的低风险工具不受拦截。
      final ToolResult read =
          await ctx.tools.call(const ToolCall(name: 'read_thing'));
      expect(read.isError, isFalse);
      // 提交工具本身是低风险，激活时也可用。
      expect(ctx.tools.get(kExitPlanModeToolName), isNotNull);

      mode.exit();
      expect((await callMut()).isError, isFalse);
      ctx.dispose();
    });
  });

  group('ExitPlanModeTool', () {
    test('批准分支：过滤空步骤、编号 id、批准后退出 Plan Mode', () async {
      ApprovalRequest? captured;
      final RuleBasedApproval approval =
          RuleBasedApproval(allow: (ApprovalRequest request) {
        captured = request;
        return true;
      });
      final SystemPrompt prompt = SystemPrompt();
      final DefaultPlanMode mode =
          DefaultPlanMode(approval: approval, prompt: prompt);
      mode.enter();
      final ExitPlanModeTool tool = ExitPlanModeTool(planMode: mode);

      final ToolResult result = await tool.call(const ToolContext(ToolCall(
        name: kExitPlanModeToolName,
        arguments: <String, Object?>{
          'goal': '安排周六',
          'steps': <Object?>['查天气', '', ' 定活动 '],
        },
      )));

      expect(result.isError, isFalse);
      expect(result.content, contains('approved'));
      expect(mode.state, PlanModeState.inactive);
      expect(prompt.sections, isEmpty);

      expect(captured, isNotNull);
      expect(captured!.toolName, 'plan');
      expect(captured!.arguments['goal'], '安排周六');
      final List<Object?> steps =
          captured!.arguments['steps']! as List<Object?>;
      expect(steps, hasLength(2));
      expect((steps.first as Map<String, Object?>)['id'], 's1');
      expect((steps.last as Map<String, Object?>)['text'], '定活动');
    });

    test('拒绝分支：保持 Plan Mode 激活并提示修订', () async {
      final DefaultPlanMode mode =
          DefaultPlanMode(approval: AutoApproval(false));
      mode.enter();
      final ExitPlanModeTool tool = ExitPlanModeTool(planMode: mode);

      final ToolResult result = await tool.call(const ToolContext(ToolCall(
        name: kExitPlanModeToolName,
        arguments: <String, Object?>{
          'goal': '安排周六',
          'steps': <Object?>['查天气'],
        },
      )));

      expect(result.isError, isFalse);
      expect(result.content, contains('revise'));
      expect(mode.state, PlanModeState.active);
    });

    test('providePlanMode 注册 exit_plan_mode 并随上下文释放撤销', () {
      final Context ctx = Context.root();
      final ToolRegistry registry = provideTools(ctx);
      providePlanMode(ctx);

      expect(registry.get(kExitPlanModeToolName), isNotNull);
      expect(ctx.planMode, isNotNull);

      ctx.dispose();
      expect(registry.length, 0);
    });
  });

  group('telemetry 埋点', () {
    test('enter / submitPlan / exit 发出对应事件', () async {
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final DefaultPlanMode mode = DefaultPlanMode(
        telemetry: telemetry,
        approval: AutoApproval(true),
      );

      mode.enter();
      await mode.submitPlan(const Plan(goal: '安排周六'));
      mode.exit();

      expect(telemetry.recent.map((TelemetryEvent e) => e.name),
          <String>['plan.entered', 'plan.submitted', 'plan.exited']);
      expect(telemetry.recent[1].data['goal'], '安排周六');
    });
  });
}
