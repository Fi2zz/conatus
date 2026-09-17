/// 引用解析与条件表达式。
///
/// 节点参数与子流程输入中的 `{{ref}}` 引用在执行前解析：
/// - `{{nodeId.path}}`：取已完成节点的输出（`path` 逐层取 map 字段）；
/// - `{{inputs.path}}`：取运行输入。
///
/// `when` 条件只支持有限语法（文档 6.3）：`==` / `!=` / `&&` / `||` /
/// `!= null`，不做函数调用与算术。引用必须指向已完成节点，否则抛
/// [WorkflowException]。
library;

import 'errors.dart';
import 'run.dart';
import 'status.dart';

final RegExp _kRef = RegExp(r'^\{\{(.+)\}\}$');
final RegExp _kCompare = RegExp(r'^(.+?)\s*==\s*(.+)$');
final RegExp _kNotEqual = RegExp(r'^(.+?)\s*!=\s*(.+)$');

/// 解析 `{{nodeId.path}}` / `{{inputs.path}}` 形式的引用。
Object? resolveReference(String ref, WorkflowRun run) {
  final parts = ref.split('.');
  final root = parts.first;
  if (root == 'inputs') {
    return _dig(run.inputs, parts.skip(1).toList(), ref);
  }
  final node = run.nodes[root];
  if (node == null) {
    throw WorkflowException('unknown-node', '引用不存在的节点: $root');
  }
  if (node.status != RunNodeStatus.completed) {
    throw WorkflowException('node-not-completed', '节点未完成: $root');
  }
  return _dig(node.outputs, parts.skip(1).toList(), ref);
}

/// 解析参数表：值整体是 `{{ref}}` 时替换为引用值；嵌套 map / list 递归
/// 处理；其余值原样保留。
Map<String, Object?> resolveArguments(
  Map<String, Object?> arguments,
  WorkflowRun run,
) {
  return arguments.map(
    (String key, Object? value) =>
        MapEntry<String, Object?>(key, resolveValue(value, run)),
  );
}

/// 解析单个值。
Object? resolveValue(Object? value, WorkflowRun run) {
  if (value is String) {
    final match = _kRef.firstMatch(value);
    if (match != null) return resolveReference(match.group(1)!, run);
    return value;
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) =>
          MapEntry<Object?, Object?>(key, resolveValue(item, run)),
    );
  }
  if (value is List) {
    return value.map((Object? item) => resolveValue(item, run)).toList();
  }
  return value;
}

/// 求值 `when` 条件表达式。
bool evaluateCondition(String expression, WorkflowRun run) {
  return expression
      .split('||')
      .map((String part) => part.trim())
      .any((String part) => _evalAnd(part, run));
}

bool _evalAnd(String expression, WorkflowRun run) {
  return expression
      .split('&&')
      .map((String part) => part.trim())
      .every((String part) => _evalComparison(part, run));
}

bool _evalComparison(String expression, WorkflowRun run) {
  final eq = _kCompare.firstMatch(expression);
  if (eq != null) {
    return _equal(_operand(eq.group(1)!, run), _literal(eq.group(2)!));
  }
  final neq = _kNotEqual.firstMatch(expression);
  if (neq != null) {
    return !_equal(_operand(neq.group(1)!, run), _literal(neq.group(2)!));
  }
  throw WorkflowException('bad-condition', '无法解析条件: $expression');
}

Object? _operand(String raw, WorkflowRun run) {
  final match = _kRef.firstMatch(raw.trim());
  if (match != null) return resolveReference(match.group(1)!, run);
  return raw.trim();
}

Object? _literal(String raw) {
  final value = raw.trim();
  if (value == 'null') return null;
  if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
    return value.substring(1, value.length - 1);
  }
  final numValue = num.tryParse(value);
  if (numValue != null) return numValue;
  return switch (value) {
    'true' => true,
    'false' => false,
    _ => value,
  };
}

bool _equal(Object? a, Object? b) => a == b;

Object? _dig(Object? value, List<String> parts, String ref) {
  var current = value;
  for (final String part in parts) {
    if (current is Map) {
      current = current[part];
    } else {
      throw WorkflowException('bad-reference', '无法解析引用: $ref');
    }
  }
  return current;
}
