/// system-prompt 插件：prompt 段与动态上下文的注册表 + 装配/渲染。
///
/// 服务键 `'systemPrompt'`。各插件在各自的上下文里注册段或上下文（都返回
/// [Disposer]，交给 `ctx.effect(...)` 即可随插件卸载自动撤销），`assemble()`
/// 按 order 升序求值，`render()` / `renderContexts()` 分别拼接段与动态上下文，
/// 并做 `{{variable}}` 插值。
library;

import 'package:conatus_core/conatus_core.dart';
import 'prompt_types.dart';

/// prompt 段与上下文的注册表。
class SystemPrompt {
  final List<PromptSection> _sections = <PromptSection>[];
  final List<PromptContext> _contexts = <PromptContext>[];

  /// 自动生成段名的序号（只增不减，remove 后不复用）。
  int _addSeq = 0;

  /// 已注册的 prompt 段（注册顺序）。
  List<PromptSection> get sections =>
      List<PromptSection>.unmodifiable(_sections);

  /// 已注册的动态上下文（注册顺序）。
  List<PromptContext> get contexts =>
      List<PromptContext>.unmodifiable(_contexts);

  /// 注册一段 prompt。同名重复注册抛 [StateError]；返回撤销函数（幂等）。
  Disposer section(PromptSection section) {
    if (_sections.any((PromptSection s) => s.name == section.name)) {
      throw StateError('prompt 段 "${section.name}" 已注册');
    }
    _sections.add(section);
    return () => _sections.remove(section);
  }

  /// 用一段纯文本创建并注册 prompt 段；[name] 缺省时自动生成唯一名。
  /// [name] 与已注册段重复时抛 [StateError]。返回该段句柄供 [remove] 使用。
  PromptSection add(String prompt, {String? name}) {
    final PromptSection created =
        PromptSection(name: name ?? _nextAddName(), text: () => prompt);
    section(created); // 注册；重复名抛 StateError
    return created;
  }

  /// 注册一份动态上下文。同名重复注册抛 [StateError]；返回撤销函数（幂等）。
  Disposer context(PromptContext context) {
    if (_contexts.any((PromptContext c) => c.name == context.name)) {
      throw StateError('prompt 上下文 "${context.name}" 已注册');
    }
    _contexts.add(context);
    return () => _contexts.remove(context);
  }

  /// 移除一段已注册的 prompt 段；未注册时返回 false（幂等）。
  bool remove(PromptSection section) => _sections.remove(section);

  /// 装配：[variables] 供渲染阶段插值。
  PromptAssembly assemble(
      {Map<String, String> variables = const <String, String>{}}) {
    final List<PromptSection> orderedSections =
        List<PromptSection>.of(_sections)
          ..sort((PromptSection a, PromptSection b) =>
              _compare(a.order, a.name, b.order, b.name));
    final List<PromptContext> orderedContexts =
        List<PromptContext>.of(_contexts)
          ..sort((PromptContext a, PromptContext b) =>
              _compare(a.order, a.name, b.order, b.name));
    return PromptAssembly(
      sections: <AssembledSection>[
        for (final PromptSection s in orderedSections)
          AssembledSection(name: s.name, text: s.text()),
      ],
      contexts: <AssembledContext>[
        for (final PromptContext c in orderedContexts)
          AssembledContext(name: c.name, text: c.text()),
      ],
      variables: variables,
    );
  }

  /// 渲染 prompt 段为一段文本，并插值 `{{variable}}`。
  String render(PromptAssembly assembly, {String separator = '\n\n'}) =>
      assembly.sections
          .map((AssembledSection s) => interpolate(s.text, assembly.variables))
          .join(separator);

  /// 渲染动态上下文为一段文本，并插值 `{{variable}}`；空文本不贡献内容。
  String renderContexts(PromptAssembly assembly, {String separator = '\n\n'}) =>
      assembly.contexts
          .map((AssembledContext c) => interpolate(c.text, assembly.variables))
          .where((String text) => text.isNotEmpty)
          .join(separator);

  /// 把 `{{name}}` 替换为 [variables] 中的值；未知占位符原样保留。
  static String interpolate(String text, Map<String, String> variables) =>
      text.replaceAllMapped(
        RegExp(r'\{\{(\w+)\}\}'),
        (Match match) => variables[match.group(1)!] ?? match.group(0)!,
      );

  static int _compare(int orderA, String nameA, int orderB, String nameB) {
    final int byOrder = orderA.compareTo(orderB);
    return byOrder != 0 ? byOrder : nameA.compareTo(nameB);
  }

  /// 生成未占用的 `add-N` 名：单调递增、remove 后不复用。
  String _nextAddName() {
    String candidate;
    do {
      candidate = 'add-${_addSeq++}';
    } while (_sections.any((PromptSection s) => s.name == candidate));
    return candidate;
  }
}

/// 将 [SystemPrompt] 作为 `'systemPrompt'` 服务提供到上下文。
SystemPrompt provideSystemPrompt(Context ctx, {SystemPrompt? prompt}) {
  final SystemPrompt resolved = prompt ?? SystemPrompt();
  ctx.provide('systemPrompt', resolved);
  return resolved;
}
