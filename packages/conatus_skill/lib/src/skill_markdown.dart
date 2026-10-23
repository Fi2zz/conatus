/// SKILL.md 的解析：frontmatter 字段、布尔文法与正文切分。
library;

import 'frontmatter.dart';
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
///
/// frontmatter 的切分与 YAML 解析交给 [parseFrontmatter]，这里只做技能字段
/// 校验；失败时 [SkillDocument.error] 直接透传解析器的文案。
SkillDocument parseSkillDocument(String text) {
  final FrontmatterDocument parsed = parseFrontmatter(text);
  if (parsed.error != null) return SkillDocument(error: parsed.error);
  return _documentFrom(parsed.fields, parsed.body);
}

SkillDocument _documentFrom(Map<String, Object?> fields, String body) {
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

String? _rejectFields(Map<String, Object?> fields) {
  final String? legacy = _legacyKeyOf(fields);
  if (legacy != null) return 'frontmatter 用了旧键 "$legacy"，请改用规范键';
  final String? invalid = _invalidIdentity(fields);
  return invalid ?? _invalidBoolean(fields);
}

String? _legacyKeyOf(Map<String, Object?> fields) {
  for (final String legacy in kSkillLegacyFrontmatterKeys) {
    if (fields.containsKey(legacy)) return legacy;
  }
  return null;
}

String? _invalidIdentity(Map<String, Object?> fields) {
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

String? _invalidBoolean(Map<String, Object?> fields) {
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
