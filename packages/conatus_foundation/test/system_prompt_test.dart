import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

PromptSection _section(String name, String text, {int order = 0}) =>
    PromptSection(name: name, order: order, text: () => text);

void main() {
  group('SystemPrompt — 注册', () {
    test('section / context 注册，重复名抛 StateError', () {
      final SystemPrompt prompt = SystemPrompt();

      final Disposer off = prompt.section(_section('a', 'A'));
      prompt.context(PromptContext(name: 'c', text: () => 'C'));

      expect(prompt.sections, hasLength(1));
      expect(prompt.contexts, hasLength(1));
      expect(() => prompt.section(_section('a', 'X')), throwsStateError);

      off();
      expect(prompt.sections, isEmpty);
    });
  });

  group('SystemPrompt — 装配与渲染', () {
    test('按 order 升序、同序按名字排序', () {
      final SystemPrompt prompt = SystemPrompt()
        ..section(_section('b', 'B', order: 10))
        ..section(_section('a', 'A', order: 10))
        ..section(_section('top', 'TOP', order: -1));

      final PromptAssembly assembly = prompt.assemble();

      expect(
        assembly.sections.map((AssembledSection s) => s.name),
        <String>['top', 'a', 'b'],
      );
      expect(prompt.render(assembly), 'TOP\n\nA\n\nB');
    });

    test('provider 每次装配重新求值', () {
      var text = 'v1';
      final SystemPrompt prompt = SystemPrompt()
        ..section(
          PromptSection(name: 'dyn', text: () => text),
        );

      expect(prompt.render(prompt.assemble()), 'v1');
      text = 'v2';
      expect(prompt.render(prompt.assemble()), 'v2');
    });

    test('render 插值变量，未知占位符原样保留', () {
      final SystemPrompt prompt = SystemPrompt()
        ..section(_section('p', '你好 {{name}}，{{missing}}'));

      final PromptAssembly assembly = prompt.assemble(
        variables: <String, String>{'name': '助手'},
      );

      expect(prompt.render(assembly), '你好 助手，{{missing}}');
    });

    test('context 一并装配', () {
      final SystemPrompt prompt = SystemPrompt()
        ..context(PromptContext(name: 'time', text: () => 'now'));

      expect(prompt.assemble().contexts.single.text, 'now');
    });

    test('renderContexts 按 order 拼接上下文并插值变量', () {
      final SystemPrompt prompt = SystemPrompt()
        ..context(PromptContext(name: 'env', text: () => '环境 A'))
        ..context(PromptContext(
            name: 'time', order: -10, text: () => '[当前时间]\n{{today}}'));

      final PromptAssembly assembly = prompt.assemble(
        variables: <String, String>{'today': '2026-09-16'},
      );

      expect(
        prompt.renderContexts(assembly),
        '[当前时间]\n2026-09-16\n\n环境 A',
      );
    });

    test('空上下文不贡献内容', () {
      final SystemPrompt prompt = SystemPrompt()
        ..context(PromptContext(name: 'empty', text: () => ''))
        ..context(PromptContext(name: 'kept', text: () => 'X'));

      expect(prompt.renderContexts(prompt.assemble()), 'X');
    });
  });

  group('SystemPrompt — add / remove', () {
    test('add 缺省名注册文本段，remove 移除', () {
      final SystemPrompt prompt = SystemPrompt();

      final PromptSection section = prompt.add('你好，世界');

      expect(prompt.sections, hasLength(1));
      expect(prompt.sections.single.name, startsWith('add-'));
      expect(prompt.render(prompt.assemble()), '你好，世界');

      expect(prompt.remove(section), isTrue);
      expect(prompt.sections, isEmpty);
      expect(prompt.render(prompt.assemble()), '');
    });

    test('add 显式 name，重复名抛 StateError', () {
      final SystemPrompt prompt = SystemPrompt();

      final PromptSection first = prompt.add('A', name: 'custom');
      expect(prompt.sections.single.name, 'custom');
      expect(first.text(), 'A');

      expect(() => prompt.add('B', name: 'custom'), throwsStateError);
    });

    test('add 缺省名不冲突且不复用', () {
      final SystemPrompt prompt = SystemPrompt()
        ..section(_section('add-1', '手动占用 add-1'));

      final PromptSection a = prompt.add('A');
      final PromptSection b = prompt.add('B');
      expect(a.name, isNot(b.name));
      // 手动注册占用了 add-1，自动生成应跳过它。
      expect(a.name, isNot('add-1'));

      prompt.remove(a);
      final PromptSection c = prompt.add('C');
      expect(c.name, isNot(a.name), reason: 'remove 后旧名不应被复用');
      expect(
        prompt.sections.map((PromptSection s) => s.name).toSet(),
        hasLength(prompt.sections.length),
        reason: '段名必须唯一',
      );
    });

    test('remove 幂等', () {
      final SystemPrompt prompt = SystemPrompt();
      final PromptSection section = prompt.add('X');

      expect(prompt.remove(section), isTrue);
      expect(prompt.remove(section), isFalse);
      expect(prompt.remove(_section('未注册', 'x')), isFalse);
    });
  });

  test('provideSystemPrompt 作为 systemPrompt 服务提供', () {
    final ctx = Context.root();
    final SystemPrompt prompt = provideSystemPrompt(ctx);

    expect(
        identical(ctx.require<SystemPrompt>('systemPrompt'), prompt), isTrue);
    ctx.dispose();
  });
}
