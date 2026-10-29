/// 子代理 profile 规则：与宿主规则合并后只能收紧。
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
    'bash',
    riskLevel: ToolRisk.high,
    handler: (ToolContext c) async {
      runs.add('bash');
      return ToolResult.success('ok');
    },
  );
  tools.fn(
    'write',
    riskLevel: ToolRisk.medium,
    handler: (ToolContext c) async {
      runs.add('write');
      return ToolResult.success('ok');
    },
  );
  return _Host(ctx, child, tools, runs);
}

const PermissionRule _denyEdit = PermissionRule(
  action: 'edit',
  resource: '*',
  effect: PermissionEffect.deny,
);

Future<ToolResult> _write(_Host host) => host.tools.call(
      const ToolCall(
        name: 'write',
        arguments: <String, Object?>{'path': 'a.txt'},
      ),
    );

Future<ToolResult> _shell(_Host host) => host.tools.call(
      const ToolCall(
        name: 'bash',
        arguments: <String, Object?>{'command': 'ls'},
      ),
    );

void main() {
  test('inherit + profile deny 生效（非空 extraRules 才装子中间件）', () async {
    final _Host host = _host();
    applySubAgentPermission(
      host.child,
      host.tools,
      SubAgentPermission.inherit,
      options: SubAgentPermissionOptions(
        gate: AutoApproval(true),
        extraRules: const <PermissionRule>[_denyEdit],
      ),
    );

    final ToolResult result = await _write(host);
    expect(result.error!.code, 'PERMISSION_DENIED');
    expect(host.runs, isEmpty);
  });

  test('auto + profile deny 仍然生效', () async {
    final _Host host = _host();
    applySubAgentPermission(
      host.child,
      host.tools,
      SubAgentPermission.auto,
      options: SubAgentPermissionOptions(
        gate: AutoApproval(true),
        extraRules: const <PermissionRule>[_denyEdit],
      ),
    );

    final ToolResult result = await _write(host);
    expect(result.error!.code, 'PERMISSION_DENIED');
    expect(host.runs, isEmpty);
  });

  test('profile allow 不能放宽宿主 deny', () async {
    final _Host host = _host(rules: const <PermissionRule>[
      PermissionRule(
        action: 'bash',
        resource: '*',
        effect: PermissionEffect.deny,
      ),
    ]);
    applySubAgentPermission(
      host.child,
      host.tools,
      SubAgentPermission.auto,
      options: SubAgentPermissionOptions(
        gate: AutoApproval(true),
        extraRules: const <PermissionRule>[
          PermissionRule(
            action: 'bash',
            resource: '*',
            effect: PermissionEffect.allow,
          ),
        ],
      ),
    );

    final ToolResult result = await _shell(host);
    expect(result.error!.code, 'PERMISSION_DENIED');
    expect(host.runs, isEmpty);
  });

  test('profile deny 覆盖宿主 allow', () async {
    final _Host host = _host(rules: const <PermissionRule>[
      PermissionRule(
        action: 'edit',
        resource: '*',
        effect: PermissionEffect.allow,
      ),
    ]);
    applySubAgentPermission(
      host.child,
      host.tools,
      SubAgentPermission.inherit,
      options: SubAgentPermissionOptions(
        gate: AutoApproval(true),
        extraRules: const <PermissionRule>[_denyEdit],
      ),
    );

    final ToolResult result = await _write(host);
    expect(result.error!.code, 'PERMISSION_DENIED');
    expect(host.runs, isEmpty);
  });

  test('inherit 无 profile 规则时保持原行为（不装子中间件）', () async {
    final _Host host = _host(rules: const <PermissionRule>[
      PermissionRule(
        action: 'edit',
        resource: '*',
        effect: PermissionEffect.allow,
      ),
    ]);
    applySubAgentPermission(
      host.child,
      host.tools,
      SubAgentPermission.inherit,
      options: SubAgentPermissionOptions(gate: AutoApproval(false)),
    );

    final ToolResult result = await _write(host);
    expect(result.isError, isFalse);
    expect(host.runs, <String>['write']);
  });
}
