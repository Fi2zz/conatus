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

  group('路径感知审批', () {
    test('pathArguments 取声明的路径参数，忽略空值与未声明项', () {
      const Tool tool = _PathTool();
      expect(
        pathArguments(
          tool,
          const ToolCall(
            name: 'read',
            arguments: <String, Object?>{'path': '/a/b.txt', 'other': 'x'},
          ),
        ),
        <String>['/a/b.txt'],
      );
      expect(
        pathArguments(tool, const ToolCall(name: 'read')),
        isEmpty,
      );
      expect(
        pathArguments(
          tool,
          const ToolCall(
              name: 'read', arguments: <String, Object?>{'path': '   '}),
        ),
        isEmpty,
      );
    });

    test('pathArguments 支持嵌套键 a.b', () {
      expect(
        pathArguments(
          const _NestedPathTool(),
          const ToolCall(
            name: 'nested',
            arguments: <String, Object?>{
              'input': <String, Object?>{'file': '/tmp/x'},
            },
          ),
        ),
        <String>['/tmp/x'],
      );
    });

    test('声明路径参数的低风险工具也进入审批，请求带 pathArgs', () async {
      final Context ctx = Context.root();
      final ToolRegistry tools = provideTools(ctx);
      tools.register(const _PathTool());
      final List<ApprovalRequest> seen = <ApprovalRequest>[];
      final Approval gate = _RecordingApproval(seen, approved: false);
      provideApproval(ctx, approval: gate);

      final ToolResult result = await tools.call(
        const ToolCall(name: 'read', arguments: <String, Object?>{'path': '/etc/passwd'}),
      );

      // read 是 low，按旧逻辑会被直接放行；声明路径参数后必须经过审批。
      expect(result.error!.code, 'APPROVAL_DENIED');
      expect(seen.single.pathArgs, <String>['/etc/passwd']);
      ctx.dispose();
    });

    test('preapproved 为 true 时直接放行，不产生审批请求', () async {
      final Context ctx = Context.root();
      final ToolRegistry tools = provideTools(ctx);
      var runs = 0;
      tools.fn(
        'read',
        pathParams: const <String>['path'],
        handler: (ToolContext c) async {
          runs++;
          return ToolResult.success('内容');
        },
      );
      final List<ApprovalRequest> seen = <ApprovalRequest>[];
      provideApproval(ctx, approval: _PreapprovedApproval(seen));

      final ToolResult result = await tools.call(
        const ToolCall(name: 'read', arguments: <String, Object?>{'path': '/data/a.txt'}),
      );

      expect(result.content, '内容');
      expect(runs, 1);
      expect(seen, isEmpty); // 未打扰用户
      ctx.dispose();
    });

    test('未声明路径参数的工具行为不变', () async {
      final Context ctx = Context.root();
      final ToolRegistry tools = provideTools(ctx);
      tools.fn('safe',
          handler: (ToolContext c) async => ToolResult.success('ok'));
      final List<ApprovalRequest> seen = <ApprovalRequest>[];
      provideApproval(ctx, approval: _PreapprovedApproval(seen));

      expect((await tools.call(const ToolCall(name: 'safe'))).isError, isFalse);
      expect(seen, isEmpty);
      ctx.dispose();
    });

    test('ApprovalRequest.toJson 含 pathArgs', () {
      final ApprovalRequest request = ApprovalRequest(
        id: 'r',
        toolName: 'read',
        pathArgs: const <String>['/a'],
      );
      expect(request.toJson()['pathArgs'], <String>['/a']);
    });
  });
}

/// 声明单个路径参数的低风险工具。
class _PathTool extends Tool {
  const _PathTool();

  @override
  String get name => 'read';

  @override
  String get description => '读取文件';

  @override
  List<String> get pathParams => const <String>['path'];

  @override
  Future<ToolResult> call(ToolContext context) async =>
      ToolResult.success('内容');
}

/// 声明嵌套路径参数的工具。
class _NestedPathTool extends Tool {
  const _NestedPathTool();

  @override
  String get name => 'nested';

  @override
  String get description => '嵌套路径';

  @override
  List<String> get pathParams => const <String>['input.file'];

  @override
  Future<ToolResult> call(ToolContext context) async =>
      ToolResult.success('');
}

/// 记录请求并按固定结果批准的替身。
class _RecordingApproval extends Approval {
  _RecordingApproval(this.seen, {required this.approved});

  final List<ApprovalRequest> seen;
  final bool approved;

  @override
  Stream<ApprovalRequest> get pending => const Stream<ApprovalRequest>.empty();

  @override
  Future<bool> request(ApprovalRequest request) async {
    seen.add(request);
    return approved;
  }
}

/// 记录被询问的请求；未询问则说明走了 preapproved 快路径。
class _PreapprovedApproval extends Approval {
  _PreapprovedApproval(this.seen);

  final List<ApprovalRequest> seen;

  @override
  Stream<ApprovalRequest> get pending => const Stream<ApprovalRequest>.empty();

  @override
  Future<bool> preapproved(ApprovalRequest request) async => true;

  @override
  Future<bool> request(ApprovalRequest request) async {
    seen.add(request);
    return false;
  }
}
