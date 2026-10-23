/// C3：git 写工具归一到 shell，`shell git *` 规则必须能拦住。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

const List<String> _gitTools = <String>[
  'git_add',
  'git_commit',
  'git_branch',
  'git_stash',
];

Map<String, Object?> _argsFor(String tool) => switch (tool) {
      'git_add' => <String, Object?>{
          'paths': <String>['a.txt'],
        },
      'git_commit' => <String, Object?>{'message': 'feat: x'},
      'git_branch' => <String, Object?>{'name': 'topic', 'create': true},
      _ => <String, Object?>{'keep': true},
    };

void main() {
  test('四个 git 写工具都映射为 shell，资源带 git 前缀', () {
    for (final String tool in _gitTools) {
      expect(permissionActionFor(tool), 'shell');
      final List<String> resources = permissionResourcesFor(
        ToolCall(name: tool, arguments: _argsFor(tool)),
        const <String>[],
      );
      expect(resources.single, startsWith('git '));
    }
  });

  test('git_branch 的 list 分支是只读命令', () {
    final List<String> resources = permissionResourcesFor(
      const ToolCall(
        name: 'git_branch',
        arguments: <String, Object?>{'list': true},
      ),
      const <String>[],
    );
    expect(resources.single, 'git branch --list');
  });

  test('action=shell resource="git *" deny 拦住四个工具', () async {
    for (final String tool in _gitTools) {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      provideTools(ctx);
      final List<String> runs = <String>[];
      ctx.tools.fn(
        tool,
        riskLevel: ToolRisk.medium,
        handler: (ToolContext c) async {
          runs.add(tool);
          return ToolResult.success('ok');
        },
      );
      ctx.provide(
        kPermissionScopeService,
        PermissionScopeSlot(
          const PermissionScope(
            rules: <PermissionRule>[
              PermissionRule(
                action: 'shell',
                resource: 'git *',
                effect: PermissionEffect.deny,
              ),
            ],
          ),
        ),
      );
      instrumentPermission(ctx, interactive: false);

      final ToolResult result = await ctx.tools.call(
        ToolCall(name: tool, arguments: _argsFor(tool)),
      );

      expect(result.error?.code, 'PERMISSION_DENIED', reason: tool);
      expect(runs, isEmpty, reason: tool);
    }
  });
}
