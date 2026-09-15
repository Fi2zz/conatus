/// 工具参数校验：按 [Tool.params] 声明检查调用参数。
///
/// 返回违规说明列表；空列表表示通过。校验覆盖必填、类型与枚举取值，并递归检查
/// 数组元素与嵌套对象字段。
library;

import 'param_spec.dart';
import 'tool.dart';

/// 校验 [args] 是否满足 [tool] 的参数声明。
List<String> validateToolArgs(Tool tool, Map<String, Object?> args) {
  final List<String> violations = <String>[];
  for (final ParamSpec spec in tool.params) {
    final String? issue = _checkProperty(spec, args, spec.name);
    if (issue != null) violations.add(issue);
  }
  return violations;
}

String? _checkProperty(
  ParamSpec spec,
  Map<Object?, Object?> container,
  String path,
) {
  if (!container.containsKey(spec.name)) {
    return spec.required ? '缺少必填参数 "$path"' : null;
  }
  final Object? value = container[spec.name];
  if (value == null) {
    return spec.required ? '参数 "$path" 不能为 null' : null;
  }
  return _checkValue(spec, value, path);
}

String? _checkValue(ParamSpec spec, Object value, String path) {
  switch (spec.type) {
    case ParamType.string:
      return value is String ? null : '参数 "$path" 期望 string';
    case ParamType.integer:
      return value is int ? null : '参数 "$path" 期望 integer';
    case ParamType.number:
      return value is num ? null : '参数 "$path" 期望 number';
    case ParamType.boolean:
      return value is bool ? null : '参数 "$path" 期望 boolean';
    case ParamType.enumeration:
      if (value is! String) return '参数 "$path" 期望 string 枚举';
      if (!spec.enumValues.contains(value)) {
        return '参数 "$path" 取值不在 ${spec.enumValues} 内';
      }
      return null;
    case ParamType.array:
      return _checkArray(spec, value, path);
    case ParamType.object:
      return _checkObject(spec, value, path);
  }
}

String? _checkArray(ParamSpec spec, Object value, String path) {
  if (value is! List) return '参数 "$path" 期望 array';
  final ParamSpec? items = spec.items;
  if (items == null) return null;
  for (int i = 0; i < value.length; i++) {
    final Object? item = value[i];
    if (item == null) {
      if (items.required) return '参数 "$path[$i]" 不能为 null';
      continue;
    }
    final String? issue = _checkValue(items, item, '$path[$i]');
    if (issue != null) return issue;
  }
  return null;
}

String? _checkObject(ParamSpec spec, Object value, String path) {
  if (value is! Map) return '参数 "$path" 期望 object';
  for (final ParamSpec child in spec.properties.values) {
    final String? issue = _checkProperty(child, value, '$path.${child.name}');
    if (issue != null) return issue;
  }
  return null;
}
