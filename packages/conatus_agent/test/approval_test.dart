import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

ApprovalRequest _request([String tool = 'danger']) =>
    ApprovalRequest(id: 'r1', toolName: tool, description: '危险操作');

void main() {
  group('内置 Approval', () {
    test('AutoApproval 批准/拒绝并记录请求', () async {
      final AutoApproval allow = AutoApproval(true);
      final AutoApproval deny = AutoApproval(false);
      final List<ApprovalRequest> seen = <ApprovalRequest>[];
      allow.pending.listen(seen.add);

      expect(await allow.request(_request()), isTrue);
      expect(await deny.request(_request()), isFalse);
      expect(allow.requests, 1);
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(1));
      await allow.close();
      await deny.close();
    });

    test('RuleBasedApproval 按规则判定', () async {
      final RuleBasedApproval approval = RuleBasedApproval(
        allow: (ApprovalRequest r) => r.toolName == 'read_file',
      );
      expect(await approval.request(_request('read_file')), isTrue);
      expect(await approval.request(_request()), isFalse);
      await approval.close();
    });

    test('AskUserApproval 识别肯定词', () async {
      final CliAskUser ask = CliAskUser();
      final AskUserApproval approval = AskUserApproval(askUser: ask);

      final Future<bool> pending = approval.request(_request());
      ask.submit('是');
      expect(await pending, isTrue);
      await approval.close();
    });

    test('AskUserApproval 否定与超时都拒绝', () async {
      final CliAskUser ask = CliAskUser();
      final AskUserApproval approval = AskUserApproval(askUser: ask);
      final Future<bool> pending = approval.request(_request());
      ask.submit('否');
      expect(await pending, isFalse);

      final AskUserApproval timingOut = AskUserApproval(
        askUser: CliAskUser(),
        timeout: const Duration(milliseconds: 10),
      );
      expect(await timingOut.request(_request()), isFalse);
      await approval.close();
      await timingOut.close();
    });

    test('requestPlan 走同一条 request', () async {
      final AutoApproval approval = AutoApproval(true);
      expect(
        await approval.requestPlan(const Plan(goal: '多步任务')),
        isTrue,
      );
      await approval.close();
    });
  });

  group('instrumentApproval / provideApproval', () {
    test('拒绝高危工具（不执行），放行低危工具', () async {
      final Context ctx = Context.root();
      final ToolRegistry tools = provideTools(ctx);
      var dangerRuns = 0;
      tools.fn(
        'danger',
        riskLevel: ToolRisk.high,
        handler: (ToolContext c) async {
          dangerRuns++;
          return ToolResult.success('deleted');
        },
      );
      tools.fn('safe',
          handler: (ToolContext c) async => ToolResult.success('ok'));
      provideApproval(ctx, approval: AutoApproval(false));

      final ToolResult safe = await tools.call(const ToolCall(name: 'safe'));
      final ToolResult denied =
          await tools.call(const ToolCall(name: 'danger'));

      expect(safe.isError, isFalse);
      expect(denied.isError, isTrue);
      expect(denied.error!.code, 'APPROVAL_DENIED');
      expect(dangerRuns, 0);
      ctx.dispose();
    });

    test('批准后高危工具执行', () async {
      final Context ctx = Context.root();
      final ToolRegistry tools = provideTools(ctx);
      tools.fn(
        'danger',
        riskLevel: ToolRisk.high,
        handler: (ToolContext c) async => ToolResult.success('deleted'),
      );
      provideApproval(ctx, approval: AutoApproval(true));

      final ToolResult result =
          await tools.call(const ToolCall(name: 'danger'));
      expect(result.content, 'deleted');
      ctx.dispose();
    });

    test('审计事件经 telemetry 记录', () async {
      final Context ctx = Context.root();
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      provideTelemetry(ctx, telemetry: telemetry);
      final ToolRegistry tools = provideTools(ctx);
      tools.fn('danger',
          riskLevel: ToolRisk.high,
          handler: (ToolContext c) async => ToolResult.success('x'));
      provideApproval(ctx, approval: AutoApproval(false));

      await tools.call(const ToolCall(name: 'danger'));

      expect(telemetry.recent.map((TelemetryEvent e) => e.name),
          containsAll(<String>['approval.requested', 'approval.decided']));
      ctx.dispose();
    });

    test('ctx.approval 可取到审批端口', () {
      final Context ctx = Context.root();
      provideTools(ctx);
      final Approval gate = provideApproval(ctx, approval: AutoApproval(true));
      expect(identical(ctx.approval, gate), isTrue);
      ctx.dispose();
    });
  });
}
