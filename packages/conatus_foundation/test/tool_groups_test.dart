import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _SimpleTool extends Tool {
  _SimpleTool(this.name, {this.riskLevel = ToolRisk.low, this.group});

  @override
  final String name;

  @override
  String get description => '';

  @override
  final ToolRisk riskLevel;

  @override
  final String? group;

  @override
  Future<ToolResult> call(ToolContext ctx) async => ToolResult.success(name);
}

void main() {
  group('ToolGroups.group', () {
    test('注册整组并可按组查询', () {
      final ToolRegistry tools = ToolRegistry();
      tools.group('web', <Tool>[_SimpleTool('search'), _SimpleTool('fetch')]);

      expect(tools.names, <String>['search', 'fetch']);
      expect(tools.groups, <String>['web']);
      expect(tools.groupOf('search'), 'web');
      expect(tools.namesIn('web'), <String>['search', 'fetch']);
      expect(tools.describeGroup('web'), hasLength(2));
      expect(tools.namesIn('nope'), isEmpty);
    });

    test('撤销函数注销整组（幂等）', () {
      final ToolRegistry tools = ToolRegistry();
      final Disposer off =
          tools.group('web', <Tool>[_SimpleTool('a'), _SimpleTool('b')]);

      off();
      off();
      expect(tools.names, isEmpty);
      expect(tools.groups, isEmpty);
    });

    test('未登记分组时回退到 Tool.group', () {
      final ToolRegistry tools = ToolRegistry()
        ..register(_SimpleTool('x', group: 'builtin'));

      expect(tools.groupOf('x'), 'builtin');
      expect(tools.namesIn('builtin'), <String>['x']);
    });
  });

  group('能力分级', () {
    test('describeWithin 只投影等级内工具', () {
      final ToolRegistry tools = ToolRegistry()
        ..register(_SimpleTool('read'))
        ..register(_SimpleTool('write', riskLevel: ToolRisk.medium))
        ..register(_SimpleTool('drop', riskLevel: ToolRisk.high));

      expect(
        tools
            .describeWithin(ToolRisk.medium)
            .map((Map<String, Object?> s) => s['name']),
        <String>['read', 'write'],
      );
      expect(
        tools
            .describeWithin(ToolRisk.high)
            .map((Map<String, Object?> s) => s['name']),
        <String>['read', 'write', 'drop'],
      );
    });

    test('guardRisk 拒绝越级工具，放行等级内工具', () async {
      final ToolRegistry tools = ToolRegistry()
        ..register(_SimpleTool('read'))
        ..register(_SimpleTool('drop', riskLevel: ToolRisk.high));
      tools.guardRisk(ToolRisk.medium);

      final ToolResult allowed = await tools.call(const ToolCall(name: 'read'));
      expect(allowed.isError, isFalse);

      final ToolResult denied = await tools.call(const ToolCall(name: 'drop'));
      expect(denied.isError, isTrue);
      expect(denied.error!.code, 'TOOL_DENIED');
    });

    test('guardRisk 对未知工具不越权处理', () async {
      final ToolRegistry tools = ToolRegistry()..guardRisk(ToolRisk.low);
      final ToolResult result = await tools.call(const ToolCall(name: 'nope'));
      expect(result.error!.code, 'UNKNOWN_TOOL');
    });
  });
}
