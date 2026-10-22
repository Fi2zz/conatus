import 'package:conatus_context/conatus_context.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _HeadCompressor implements ContentCompressor {
  @override
  ContentKind get kind => ContentKind.text;

  @override
  CompressionDraft? compress(String input, CompressionBudget budget) =>
      CompressionDraft(input.substring(0, 10), itemsOmitted: 90);
}

class _EchoTool extends Tool {
  @override
  String get name => 'echo';

  @override
  String get description => 'echo';

  @override
  List<ParamSpec> get params => <ParamSpec>[ParamSpec.string('text')];

  @override
  Future<ToolResult> call(ToolContext context) async =>
      ToolResult.success(context.str('text'), value: <String, Object?>{'ok': true});
}

class _ListValueTool extends Tool {
  @override
  String get name => 'list';

  @override
  String get description => 'list value';

  @override
  Future<ToolResult> call(ToolContext context) async =>
      ToolResult.success(List<String>.filled(100, 'x').join(),
          value: <Object?>[1, 2, 3]);
}

Context _app({
  ContextCompressionConfig? config,
  List<ContentCompressor>? compressors,
}) {
  final Context app = Context.root();
  provideTools(app);
  app.effect(() => app.tools.register(_EchoTool()));
  app.effect(() => app.tools.register(_ListValueTool()));
  provideContextCompression(
    app,
    config: config ?? const ContextCompressionConfig(minChars: 10),
    compressors: compressors ?? <ContentCompressor>[_HeadCompressor()],
  );
  addTearDown(app.dispose);
  return app;
}

void main() {
  final String text = List<String>.filled(100, 'x').join();

  test('中间件压缩结果并合并元数据', () async {
    final Context app = _app();
    final ToolResult r = await app.tools.call(
        ToolCall(name: 'echo', arguments: <String, Object?>{'text': text}));
    expect(r.content, contains('<<ctx:'));
    final Map<String, Object?> value = r.value! as Map<String, Object?>;
    expect(value['contextCompressed'], true);
    expect(value['ok'], true);
    expect(app.contextCompressor, isNotNull);
  });

  test('value 不是 Map 时不抛异常', () async {
    final Context app = _app();
    final ToolResult r = await app.tools.call(const ToolCall(name: 'list'));
    expect(r.isError, false);
    expect(r.content, contains('<<ctx:'));
    final Map<String, Object?> value = r.value! as Map<String, Object?>;
    expect(value['originalValue'], <Object?>[1, 2, 3]);
  });

  test('enabled=false 时完全透传', () async {
    final Context app = _app(
        config: const ContextCompressionConfig(minChars: 10, enabled: false));
    final ToolResult r = await app.tools.call(
        ToolCall(name: 'echo', arguments: <String, Object?>{'text': text}));
    expect(r.content, text);
  });

  test('保护工具透传', () async {
    final Context app = _app(
        config: const ContextCompressionConfig(
            minChars: 10, protectedTools: <String>{'echo'}));
    final ToolResult r = await app.tools.call(
        ToolCall(name: 'echo', arguments: <String, Object?>{'text': text}));
    expect(r.content, text);
  });

  test('上下文释放后中间件与工具撤销', () async {
    final Context base = Context.root();
    provideTools(base);
    base.effect(() => base.tools.register(_EchoTool()));
    final Context child = base.plugin('compression', (Context child) {
      provideContextCompression(
        child,
        config: const ContextCompressionConfig(minChars: 10),
        compressors: <ContentCompressor>[_HeadCompressor()],
      );
    });
    expect(base.tools.get('context_retrieve'), isNotNull);
    child.dispose();
    expect(base.tools.get('context_retrieve'), isNull);
    final ToolResult r = await base.tools.call(
        ToolCall(name: 'echo', arguments: <String, Object?>{'text': text}));
    expect(r.content, text);
    base.dispose();
  });
}
