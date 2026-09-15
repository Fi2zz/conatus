/// 上下文管理的类型词汇：prompt 段/上下文的注册项与装配结果。
library;

/// 一段可注册的 system prompt 段。
///
/// [order] 升序拼接，同序按 [name] 的码位序；[text] 是每次装配都重新求值的
/// provider（可引用 `{{variable}}` 占位符，由渲染阶段插值）。
class PromptSection {
  const PromptSection({
    required this.name,
    this.order = 0,
    required this.text,
  });

  /// 唯一名字（重复注册抛错）。
  final String name;

  /// 排序权重（升序）。
  final int order;

  /// 段文本 provider。
  final String Function() text;
}

/// 一份动态模型上下文，装配为独立贡献项。
class PromptContext {
  const PromptContext({
    required this.name,
    this.order = 0,
    required this.text,
  });

  /// 唯一名字（重复注册抛错）。
  final String name;

  /// 排序权重（升序）。
  final int order;

  /// 上下文文本 provider；空串不贡献内容。
  final String Function() text;
}

/// 已解析的一段 prompt 段。
class AssembledSection {
  const AssembledSection({required this.name, required this.text});

  /// 贡献段的名字。
  final String name;

  /// 已解析（尚未插值）的文本。
  final String text;
}

/// 已解析的一份动态上下文。
class AssembledContext {
  const AssembledContext({required this.name, required this.text});

  /// 贡献项的名字。
  final String name;

  /// 已解析的文本。
  final String text;
}

/// 一次装配的完整结果：段、上下文与插值变量。
class PromptAssembly {
  const PromptAssembly({
    required this.sections,
    required this.contexts,
    required this.variables,
  });

  /// 已排序的 prompt 段。
  final List<AssembledSection> sections;

  /// 已排序的动态上下文。
  final List<AssembledContext> contexts;

  /// 渲染时用于 `{{name}}` 插值的变量。
  final Map<String, String> variables;
}
