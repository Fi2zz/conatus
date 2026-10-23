/// 通用 frontmatter 解析：首行 `---` 围栏内的 YAML 映射 + 围栏外正文。
///
/// 与具体产物无关：技能（`SKILL.md`）、命令（`.nava/commands`）与子智能体
/// （`.nava/agents`）都只是「frontmatter + Markdown 正文」，各自在
/// [FrontmatterDocument.fields] 之上做自己的字段校验。
library;

import 'package:yaml/yaml.dart';

/// 一次 frontmatter 解析的结果。
///
/// 解析失败时 [error] 非空、[fields] 为空映射；[body] 始终尽力给出（可能为空）。
class FrontmatterDocument {
  /// 构造结果。
  const FrontmatterDocument({
    required this.fields,
    required this.body,
    this.error,
  });

  /// frontmatter 里的键值映射；失败时为空。
  final Map<String, Object?> fields;

  /// 去掉 frontmatter 并 `trim()` 后的正文。
  final String body;

  /// 失败原因；为 `null` 表示解析成功。
  final String? error;
}

/// 解析一份 Markdown 文本的 frontmatter。
///
/// 首行必须恰好是 `---`，其后找下一个 `---` 作为闭合行，两行之间按 YAML
/// 解析且必须是键值映射；闭合行之后是正文。CRLF 与 LF 都接受。
FrontmatterDocument parseFrontmatter(String text) {
  final List<String> lines = text.split('\n');
  if (lines.isEmpty || _stripCr(lines.first) != '---') {
    return _failure('缺少 frontmatter：首行必须是 ---', text.trim());
  }
  final int close = _closingFence(lines);
  if (close < 0) {
    return _failure('缺少 frontmatter 闭合行：需要一行 ---');
  }
  final String body = lines.sublist(close + 1).join('\n').trim();
  return _parseYaml(lines.sublist(1, close).join('\n'), body);
}

/// 构造一个失败结果：字段为空映射，正文尽力保留。
FrontmatterDocument _failure(String message, [String body = '']) =>
    FrontmatterDocument(
      fields: <String, Object?>{},
      body: body,
      error: message,
    );

FrontmatterDocument _parseYaml(String source, String body) {
  final Object? value;
  try {
    value = loadYaml(source);
  } on Object catch (error) {
    return _failure('frontmatter 不是合法 YAML：$error', body);
  }
  if (value is! Map) {
    return _failure('frontmatter 必须是键值映射', body);
  }
  return FrontmatterDocument(fields: _stringKeys(value), body: body);
}

/// 只保留字符串键：非字符串键对齐 YAML 语义无法用 `ctx.fields[name]` 取到。
Map<String, Object?> _stringKeys(Map<Object?, Object?> raw) {
  final Map<String, Object?> fields = <String, Object?>{};
  for (final Object? key in raw.keys) {
    if (key is String) fields[key] = raw[key];
  }
  return fields;
}

int _closingFence(List<String> lines) {
  for (int index = 1; index < lines.length; index++) {
    if (_stripCr(lines[index]) == '---') return index;
  }
  return -1;
}

String _stripCr(String line) =>
    line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
