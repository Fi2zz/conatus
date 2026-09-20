/// LLM 输出 → 候选意图的触发条件。
library;

import 'dart:convert';

/// 让模型生成触发条件的默认 system prompt。
const String kDefaultIntentSpecPrompt = '你是意图分析助手。给定一个能力（技能或工具），生成用户会用自然语言触发它的'
    '正则模式与示例语句。只输出 JSON，形如 '
    '{"patterns": ["^(查天气|今天天气)"], "examples": ["今天天气怎么样"]}。';

/// LLM 生成的触发条件：正则模式与示例语句。
///
/// 只承载「怎么触发」，不承载「触发后做什么」——动作必须由人绑定：模型不知道
/// 部署方有哪些工具、参数怎么填。
class IntentSpec {
  /// 构造触发条件。
  const IntentSpec({
    this.name,
    this.description,
    this.patterns = const <String>[],
    this.examples = const <String>[],
  });

  /// 从 JSON 还原；非字符串项被丢弃（LLM 输出不可信）。
  factory IntentSpec.fromJson(Map<String, Object?> json) => IntentSpec(
        name: textOf(json['name']),
        description: textOf(json['description']),
        patterns: stringsOf(json['patterns']),
        examples: stringsOf(json['examples']),
      );

  /// 建议的意图名（snake_case）；模型没给时为 null。
  final String? name;

  /// 建议的描述；模型没给时为 null。
  final String? description;

  /// 正则模式源码。
  final List<String> patterns;

  /// 示例语句。
  final List<String> examples;

  /// 是否什么都没生成出来。
  bool get isEmpty => patterns.isEmpty && examples.isEmpty;

  /// 编译成正则；非法模式被丢弃——一条坏模式不该让整条候选作废。
  List<Pattern> compilePatterns() {
    final List<Pattern> compiled = <Pattern>[];
    for (final String source in patterns) {
      final Pattern? pattern = tryCompilePattern(source);
      if (pattern != null) compiled.add(pattern);
    }
    return compiled;
  }

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (patterns.isNotEmpty) 'patterns': patterns,
        if (examples.isNotEmpty) 'examples': examples,
      };
}

/// 从模型回复里解析 [IntentSpec]。
///
/// 解析不出来时返回空 spec 而不是抛异常——候选生成是增强路径，不该打断主流程。
IntentSpec parseIntentSpec(String content) {
  final Object? decoded = decodeJsonIn(content);
  if (decoded is! Map) return const IntentSpec();
  return IntentSpec.fromJson(Map<String, Object?>.from(decoded));
}

/// 截出文本里的第一个 JSON 值并解码；解析不出返回 null。
///
/// 模型常把 JSON 包在说明文字或 ``` 围栏里，因此不做严格解析，只取第一个
/// `{` / `[` 到最后一个 `}` / `]` 之间的内容。
Object? decodeJsonIn(String content) {
  final int objectStart = content.indexOf('{');
  final int arrayStart = content.indexOf('[');
  final int start = _earliest(objectStart, arrayStart);
  final int end = _latest(content.lastIndexOf('}'), content.lastIndexOf(']'));
  if (start < 0 || end <= start) return null;
  try {
    return jsonDecode(content.substring(start, end + 1));
  } on FormatException {
    return null;
  }
}

/// 编译正则；非法模式返回 null。
Pattern? tryCompilePattern(String source) {
  try {
    return RegExp(source);
  } on FormatException {
    return null;
  }
}

/// 取字符串数组；非列表返回空列表，非字符串项被丢弃。
List<String> stringsOf(Object? value) =>
    value is List ? value.whereType<String>().toList() : const <String>[];

/// 取非空字符串；否则返回 null。
String? textOf(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int _earliest(int a, int b) {
  if (a < 0) return b;
  if (b < 0) return a;
  return a < b ? a : b;
}

int _latest(int a, int b) => a > b ? a : b;
