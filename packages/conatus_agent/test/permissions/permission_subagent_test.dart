/// 子代理权限：非 inherit 档仍受宿主 deny 规则约束。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _Host {
  _Host(this.ctx, this.child, this.tools, this.runs);

  final Context ctx;
  final Context child;
  final ToolRegistry tools;
  final List<String> runs;
}

_Host _host({List<PermissionRule> rules = const <PermissionRule>[]}) {
  final Context ctx = Context.root();
  addTearDown(ctx.dispose);
  ctx.provide(
    kPermissionScopeService,
    PermissionScopeSlot(PermissionScope(rules: rules)),
  );
  final Context child = ctx.plugin('sub', (Context c) {});
  final ToolRegistry tools = ToolRegistry();
  final List<String> runs = <String>[];
  tools.fn(
    'run_command',
    riskLevel: ToolRisk.high,
    handler: (ToolContext c) async {
      runs.add('run_command');
      return ToolResult.success('ok');
    },
  );
  tools.fn(
    'write_file',
    riskLevel: ToolRisk.medium,
    handler: (ToolContext c) async {
      runs.add('write_file');
      return ToolResult.success('ok');
    },
  );
  return _Host(ctx, child, tools, runs);
}

void main() {
  test('宿主 deny shell 在子代理 auto 档仍然生效', () async {
    final _Host host = _host(rules: const <PermissionRule>[
      PermissionRule(
        action: 'shell',
        resource: '*',
        effect: PermissionEffect.deny,
      ),
    ]);
    applySubAgentPermission(
      host.child,
      host.tools,
      SubAgentPermission.auto,
      gate: AutoApproval(true),
    );

    final ToolResult result = await host.tools.call(
      const ToolCall(
        name: 'run_command',
        arguments: <String, Object?>{'command': 'ls'},
      ),
    );
    expect(result.error!.code, 'PERMISSION_DENIED');
    expect(host.runs, isEmpty);
  });

  test('auto 档在无 deny 时放行高危工具', () async {
    final _Host host = _host();
    applySubAgentPermission(
      host.child,
      host.tools,
      SubAgentPermission.auto,
      gate: AutoApproval(true),
    );

    final ToolResult result = await host.tools.call(
      const ToolCall(
        name: 'run_command',
        arguments: <String, Object?>{'command': 'ls'},
      ),
    );
    expect(result.isError, isFalse);
    expect(host.runs, <String>['run_command']);
  });

  test('readonly 档仍拒绝 medium 工具', () async {
    final _Host host = _host();
    applySubAgentPermission(
      host.child,
      host.tools,
      SubAgentPermission.readonly,
      gate: AutoApproval(true),
    );

    final ToolResult result = await host.tools.call(
      const ToolCall(
        name: 'write_file',
        arguments: <String, Object?>{'path': 'a.txt'},
      ),
    );
    expect(result.isError, isTrue);
    expect(host.runs, isEmpty);
  });

  test('ask 档在宿主 deny 前仍直接拒绝（deny 优先于询问）', () async {
    final _Host host = _host(rules: const <PermissionRule>[
      PermissionRule(
        action: 'shell',
        resource: '*',
        effect: PermissionEffect.deny,
      ),
    ]);
    applySubAgentPermission(
      host.child,
      host.tools,
      SubAgentPermission.ask,
      gate: AutoApproval(true),
    );

    final ToolResult result = await host.tools.call(
      const ToolCall(
        name: 'run_command',
        arguments: <String, Object?>{'command': 'ls'},
      ),
    );
    expect(result.error!.code, 'PERMISSION_DENIED');
    expect(host.runs, isEmpty);
  });

  test('ask 档不继承父级 allow：仍逐次询问', () async {
    final _Host host = _host(rules: const <PermissionRule>[
      PermissionRule(
        action: 'shell',
        resource: '*',
        effect: PermissionEffect.allow,
      ),
    ]);
    applySubAgentPermission(
      host.child,
      host.tools,
      SubAgentPermission.ask,
      gate: AutoApproval(false),
    );

    final ToolResult result = await host.tools.call(
      const ToolCall(
        name: 'run_command',
        arguments: <String, Object?>{'command': 'ls'},
      ),
    );

    expect(
      result.isError,
      isTrue,
      reason: '父级 allow 不能让 ask 档跳过审批',
    );
    expect(host.runs, isEmpty);
  });
}
