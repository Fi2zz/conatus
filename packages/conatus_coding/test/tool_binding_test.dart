import 'package:conatus_coding/conatus_coding.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('toolsAsBindings', () {
    test('global 为 tools，函数名即工具名', () {
      final ToolRegistry tools = ToolRegistry();
      tools.register(const _EchoTool());

      final List<CodeBindingNamespace> namespaces = toolsAsBindings(tools);

      expect(namespaces, hasLength(1));
      expect(namespaces.single.global, 'tools');
      expect(namespaces.single.functions.keys, contains('echo'));
    });

    test('调用绑定返回工具结果的文本内容', () async {
      final ToolRegistry tools = ToolRegistry();
      tools.register(const _EchoTool());

      final CodeBindingNamespace ns = toolsAsBindings(tools).single;
      final Object? value = await ns.functions['echo']!(<String, Object?>{
        'text': 'hi',
      });

      expect(value, 'hi');
    });
  });
}

class _EchoTool extends Tool {
  const _EchoTool();

  @override
  String get name => 'echo';

  @override
  String get description => '回显文本';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('text', required: true),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async =>
      ToolResult.success(ctx.str('text'));
}
