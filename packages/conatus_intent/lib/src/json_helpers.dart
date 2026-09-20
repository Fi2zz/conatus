/// JSON 字段读取辅助（内部共享，不对外导出）。
///
/// 意图配置里区分「必填缺失」与「类型错误」：必填字段缺失或类型错误抛
/// [IntentException]（`missing-field` / `bad-type`）；可选字段宽容降级
/// （null / 空集合），与 `conatus_workflow` 的解析风格一致。
library;

import 'errors.dart';

/// 读取必填字符串字段；缺失或类型错误抛 [IntentException]。
String requiredString(Map<String, Object?> json, String field) {
  final Object? value = json[field];
  if (value is String && value.isNotEmpty) return value;
  throw value == null
      ? IntentException('missing-field', '缺少必填字段: $field')
      : IntentException('bad-type', '字段类型错误: $field');
}

/// 读取必填字符串键 map 字段；缺失或类型错误抛 [IntentException]。
Map<String, Object?> requiredStringMap(
  Map<String, Object?> json,
  String field,
) {
  final Object? value = json[field];
  if (value is Map) return Map<String, Object?>.from(value);
  throw value == null
      ? IntentException('missing-field', '缺少必填字段: $field')
      : IntentException('bad-type', '字段类型错误: $field');
}

/// 读取可选字符串列表字段；非列表降级为空列表，非字符串项被丢弃。
List<String> optionalStringList(Map<String, Object?> json, String field) {
  final Object? value = json[field];
  if (value is! List) return const <String>[];
  return value.whereType<String>().toList();
}

/// 读取可空数字列表字段；非列表（含 null）返回 null。
List<double>? nullableDoubleList(Map<String, Object?> json, String field) {
  final Object? value = json[field];
  if (value is! List) return null;
  return value.whereType<num>().map((num item) => item.toDouble()).toList();
}
