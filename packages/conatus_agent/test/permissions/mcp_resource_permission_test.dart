/// MCP 资源工具按 server 细化权限资源：可只拒绝一台 server。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

ToolCall _call(String name, Map<String, Object?> arguments) =>
    ToolCall(name: name, arguments: arguments);

void main() {
  test('list_mcp_resources：资源是 server 名，缺省 *', () {
    expect(permissionActionFor('list_mcp_resources'), 'list_mcp_resources');
    expect(
      permissionResourcesFor(
        _call('list_mcp_resources', <String, Object?>{'server': 'sentry'}),
        const <String>[],
      ),
      <String>['sentry'],
    );
    expect(
      permissionResourcesFor(
        _call('list_mcp_resources', const <String, Object?>{}),
        const <String>[],
      ),
      <String>['*'],
    );
  });

  test('read_mcp_resource：资源是 <server>:<uri>', () {
    expect(permissionActionFor('read_mcp_resource'), 'read_mcp_resource');
    expect(
      permissionResourcesFor(
        _call('read_mcp_resource', <String, Object?>{
          'server': 'sentry',
          'uri': 'file:///a',
        }),
        const <String>[],
      ),
      <String>['sentry:file:///a'],
    );
    expect(
      permissionResourcesFor(
        _call('read_mcp_resource', <String, Object?>{'server': 'sentry'}),
        const <String>[],
      ),
      <String>['sentry'],
    );
  });

  test('规则可拒绝单台 server，其他 server 照常放行', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    provideTools(ctx);
    final List<String> runs = <String>[];
    ctx.tools.fn(
      'list_mcp_resources',
      handler: (ToolContext call) async {
        runs.add('${call.arguments['server']}');
        return ToolResult.success('ok');
      },
    );
    ctx.provide(
      kPermissionScopeService,
      PermissionScopeSlot(
        const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'list_mcp_resources',
              resource: 'sentry',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      ),
    );
    instrumentPermission(ctx, interactive: false);

    final ToolResult denied = await ctx.tools.call(
      _call('list_mcp_resources', <String, Object?>{'server': 'sentry'}),
    );
    expect(denied.error?.code, 'PERMISSION_DENIED');
    final ToolResult allowed = await ctx.tools.call(
      _call('list_mcp_resources', <String, Object?>{'server': 'github'}),
    );
    expect(allowed.isError, isFalse);
    expect(runs, <String>['github']);
  });

  test('read 规则 sentry:* 只拦该 server 的资源', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    provideTools(ctx);
    ctx.tools.fn(
      'read_mcp_resource',
      handler: (ToolContext call) async => ToolResult.success('ok'),
    );
    ctx.provide(
      kPermissionScopeService,
      PermissionScopeSlot(
        const PermissionScope(
          rules: <PermissionRule>[
            PermissionRule(
              action: 'read_mcp_resource',
              resource: 'sentry:*',
              effect: PermissionEffect.deny,
            ),
          ],
        ),
      ),
    );
    instrumentPermission(ctx, interactive: false);

    final ToolResult denied = await ctx.tools.call(
      _call('read_mcp_resource', <String, Object?>{
        'server': 'sentry',
        'uri': 'file:///a',
      }),
    );
    expect(denied.error?.code, 'PERMISSION_DENIED');
    final ToolResult allowed = await ctx.tools.call(
      _call('read_mcp_resource', <String, Object?>{
        'server': 'github',
        'uri': 'file:///a',
      }),
    );
    expect(allowed.isError, isFalse);
  });
}
