import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('ToolFn.fn', () {
    test('一行注册并执行，声明进入 schema', () async {
      final ToolRegistry tools = ToolRegistry();
      tools.fn(
        'echo',
        description: '回显输入',
        params: <ParamSpec>[ParamSpec.string('text', required: true)],
        handler: (ToolContext ctx) async =>
            ToolResult.success(ctx.str('text'), value: ctx.str('text')),
      );

      final Tool? tool = tools.get('echo');
      expect(tool, isNotNull);
      expect(tool!.description, '回显输入');
      expect(tool.riskLevel, ToolRisk.low);
      expect(tool.group, isNull);
      expect(
        (tool.toSchema()['parameters']! as Map<String, Object?>)['required'],
        <String>['text'],
      );

      final ToolResult result = await tools.call(
        const ToolCall(
            name: 'echo', arguments: <String, Object?>{'text': 'hi'}),
      );
      expect(result.content, 'hi');
      expect(result.value, 'hi');
    });

    test('参数校验沿用注册表：缺失必填 → INVALID_ARGS', () async {
      final ToolRegistry tools = ToolRegistry();
      var runs = 0;
      tools.fn(
        'need',
        params: <ParamSpec>[ParamSpec.integer('n', required: true)],
        handler: (ToolContext ctx) async {
          runs++;
          return ToolResult.success('${ctx.require<int>('n')}');
        },
      );

      final ToolResult result = await tools.call(const ToolCall(name: 'need'));

      expect(runs, 0);
      expect(result.error!.code, 'INVALID_ARGS');
    });

    test('风险等级与分组可声明', () {
      final ToolRegistry tools = ToolRegistry();
      tools.fn(
        'danger',
        riskLevel: ToolRisk.high,
        group: 'admin',
        handler: (ToolContext ctx) async => ToolResult.success(''),
      );

      expect(tools.get('danger')!.riskLevel, ToolRisk.high);
      expect(tools.get('danger')!.group, 'admin');
    });

    test('返回的 Disposer 注销工具（幂等）', () {
      final ToolRegistry tools = ToolRegistry();
      final Disposer off = tools.fn(
        'echo',
        handler: (ToolContext ctx) async => ToolResult.success(''),
      );

      off();
      off();
      expect(tools.get('echo'), isNull);
    });

    test('配合 ctx.effect 随上下文释放自动注销', () {
      final Context ctx = Context.root();
      final ToolRegistry tools = provideTools(ctx);

      ctx.effect(() => ctx.tools.fn(
            'echo',
            handler: (ToolContext c) async => ToolResult.success(''),
          ));

      expect(tools.get('echo'), isNotNull);
      ctx.dispose();
      expect(tools.get('echo'), isNull);
    });
  });
}
