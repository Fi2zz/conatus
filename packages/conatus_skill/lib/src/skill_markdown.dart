/// SKILL.md 的解析：frontmatter 字段、布尔文法与正文切分。
library;

import 'package:yaml/yaml.dart';

import 'skill_types.dart';

/// 已废弃的 camelCase 键：出现即整条丢弃（与 dsh 的语义一致）。
const Set<String> kSkillLegacyFrontmatterKeys = <String>{
  'disableModelInvocation',
  'modelInvocable',
  'userInvocable',
};

/// 通过校验的 frontmatter。
class SkillFrontmatter {
  /// 构造 frontmatter。
  const SkillFrontmatter({
    required this.name,
    required this.description,
    this.whenToUse,
    this.metadata,
    this.modelInvocable = true,
  });

  /// 技能名（kebab-case）。
  final String name;

  /// 一行描述。
  final String description;

  /// 适用时机的补充说明。
  final String? whenToUse;

  /// 任意附加元数据，原样保留。
  final Map<String, Object?>? metadata;

  /// 模型是否可以调用 `skill` 工具加载它。
  final bool modelInvocable;
}

/// 一次解析的结果：失败时 [error] 非空，调用方应丢弃该条目。
class SkillDocument {
  /// 构造结果。
  const SkillDocument({this.frontmatter, this.body = '', this.error});

  /// 通过校验的 frontmatter。
  final SkillFrontmatter? frontmatter;

  /// 去 frontmatter 并 `trim()` 后的正文。
  final String body;

  /// 丢弃原因；为 `null` 表示解析成功。
  final String? error;
}

/// 解析一份技能文本。
SkillDocument parseSkillDocument(String text) {
  final _Frontmatter? split = _splitFrontmatter(text);
  if (split == null) {
    return const SkillDocument(error: '缺少 frontmatter：首行必须是 ---');
  }
  final _YamlResult yaml = _loadYaml(split.source);
  if (yaml.error != null) {
    return SkillDocument(error: 'frontmatter 不是合法 YAML：${yaml.error}');
  }
  final Object? parsed = yaml.value;
  if (parsed is! Map) {
    return const SkillDocument(error: 'frontmatter 必须是键值映射');
  }
  return _documentFrom(Map<Object?, Object?>.from(parsed), split.body);
}

SkillDocument _documentFrom(Map<Object?, Object?> fields, String body) {
  final String? rejection = _rejectFields(fields);
  if (rejection != null) return SkillDocument(error: rejection);
  return SkillDocument(
    frontmatter: SkillFrontmatter(
      name: fields['name']! as String,
      description: (fields['description']! as String).trim(),
      whenToUse: _optionalText(fields['whenToUse']),
      metadata: _optionalMetadata(fields['metadata']),
      modelInvocable:
          !_readBoolean(fields['disable-model-invocation'] ?? false),
    ),
    body: body,
  );
}

String? _rejectFields(Map<Object?, Object?> fields) {
  final String? legacy = _legacyKeyOf(fields);
  if (legacy != null) return 'frontmatter 用了旧键 "$legacy"，请改用规范键';
  final String? invalid = _invalidIdentity(fields);
  return invalid ?? _invalidBoolean(fields);
}

String? _legacyKeyOf(Map<Object?, Object?> fields) {
  for (final String legacy in kSkillLegacyFrontmatterKeys) {
    if (fields.containsKey(legacy)) return legacy;
  }
  return null;
}

String? _invalidIdentity(Map<Object?, Object?> fields) {
  final Object? name = fields['name'];
  if (name is! String || !isSkillName(name)) {
    return 'name 缺失或不是 kebab-case 技能名';
  }
  final Object? description = fields['description'];
  if (description is! String || description.trim().isEmpty) {
    return 'description 缺失或为空';
  }
  return null;
}

String? _invalidBoolean(Map<Object?, Object?> fields) {
  try {
    _readBoolean(fields['disable-model-invocation'] ?? false);
    return null;
  } on FormatException catch (error) {
    return error.message;
  }
}

bool _readBoolean(Object? value) {
  if (value is bool) return value;
  if (value is num && (value == 1 || value == 0)) return value == 1;
  if (value is String) {
    final String normalized = value.trim().toLowerCase();
    if (const <String>{'true', 'yes', 'on', '1'}.contains(normalized)) {
      return true;
    }
    if (const <String>{'false', 'no', 'off', '0'}.contains(normalized)) {
      return false;
    }
  }
  throw FormatException('不是合法布尔值：$value');
}

String? _optionalText(Object? value) {
  if (value is! String) return null;
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Map<String, Object?>? _optionalMetadata(Object? value) {
  if (value is! Map) return null;
  return Map<String, Object?>.from(value);
}

class _Frontmatter {
  const _Frontmatter(this.source, this.body);

  final String source;
  final String body;
}

_Frontmatter? _splitFrontmatter(String text) {
  final List<String> lines = text.split('\n');
  if (lines.isEmpty || _stripCr(lines.first) != '---') return null;
  for (int index = 1; index < lines.length; index++) {
    if (_stripCr(lines[index]) == '---') {
      return _Frontmatter(
        lines.sublist(1, index).join('\n'),
        lines.sublist(index + 1).join('\n').trim(),
      );
    }
  }
  return null;
}

String _stripCr(String line) =>
    line.endsWith('\r') ? line.substring(0, line.length - 1) : line;

class _YamlResult {
  const _YamlResult(this.value, this.error);

  final Object? value;
  final String? error;
}

_YamlResult _loadYaml(String source) {
  try {
    return _YamlResult(loadYaml(source), null);
  } on Object catch (error) {
    return _YamlResult(null, '$error');
  }
}
