/// JSON 字段读取辅助（内部共享，不对外导出）。
///
/// 声明式流程定义需要区分「必填缺失」与「类型错误」：
/// - 必填字段缺失或类型错误抛 [WorkflowException]（`missing-field` /
///   `bad-type`）；
/// - 可选字段宽容降级（null / 空集合），保持与 `conatus_team` 的
///   解析风格一致。
library;

import 'errors.dart';

/// 读取必填字符串字段；缺失或类型错误抛 [WorkflowException]。
String requiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is String && value.isNotEmpty) return value;
  throw value == null
      ? WorkflowException('missing-field', '缺少必填字段: $field')
      : WorkflowException('bad-type', '字段类型错误: $field');
}

/// 读取必填整数字段；缺失或类型错误抛 [WorkflowException]。
int requiredInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is int) return value;
  throw value == null
      ? WorkflowException('missing-field', '缺少必填字段: $field')
      : WorkflowException('bad-type', '字段类型错误: $field');
}

/// 读取必填字符串列表字段；缺失或类型错误抛 [WorkflowException]。
List<String> requiredStringList(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is List) {
    return value.map((Object? item) {
      if (item is String) return item;
      throw WorkflowException('bad-type', '字段类型错误: $field');
    }).toList();
  }
  throw value == null
      ? WorkflowException('missing-field', '缺少必填字段: $field')
      : WorkflowException('bad-type', '字段类型错误: $field');
}

/// 读取可选字符串字段；非字符串（含 null）降级为 null。
String? optionalString(Map<String, Object?> json, String field) {
  final value = json[field];
  return value is String ? value : null;
}

/// 读取可选字符串列表字段；非列表降级为空列表。
List<String> optionalStringList(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! List) return const <String>[];
  return value.whereType<String>().toList();
}

/// 读取可空字符串列表字段；非列表（含 null）返回 null。
///
/// 用于语义上区分「未指定」（null）与「空列表」（明确不给）的字段。
List<String>? nullableStringList(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! List) return null;
  return value.whereType<String>().toList();
}

/// 读取可选字符串键 map 字段；非 map 降级为空 map。
Map<String, Object?> optionalStringMap(
  Map<String, Object?> json,
  String field,
) {
  final value = json[field];
  if (value is! Map) return const <String, Object?>{};
  return Map<String, Object?>.from(value);
}

/// 读取必填字符串键 map 字段；缺失或类型错误抛 [WorkflowException]。
Map<String, Object?> requiredStringMap(
  Map<String, Object?> json,
  String field,
) {
  final value = json[field];
  if (value is Map) return Map<String, Object?>.from(value);
  throw value == null
      ? WorkflowException('missing-field', '缺少必填字段: $field')
      : WorkflowException('bad-type', '字段类型错误: $field');
}

/// 读取必填时间字段；缺失、非字符串或格式错误抛 [WorkflowException]。
DateTime requiredDateTime(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
    throw WorkflowException('bad-type', '字段类型错误: $field');
  }
  throw value == null
      ? WorkflowException('missing-field', '缺少必填字段: $field')
      : WorkflowException('bad-type', '字段类型错误: $field');
}

/// 读取可选时间字段；缺失或格式错误返回 null。
DateTime? optionalDateTime(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is String) return DateTime.tryParse(value);
  return null;
}
