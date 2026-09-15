/// 工具基类与类型安全的参数上下文。
///
/// 作者继承 [Tool] 声明形状（名字、简介、风险、分组、参数）与执行体
/// [Tool.call]；执行体拿到 [ToolContext]，按需取参，取参失败抛
/// [ToolArgumentException]，由注册表统一收敛。
library;

import 'param_spec.dart';
import 'parameter_schema.dart';
import 'tool_types.dart';

/// 参数缺失、类型不符或取值非法时抛出。
class ToolArgumentException implements Exception {
  const ToolArgumentException(this.message);

  /// 人可读的失败说明。
  final String message;

  @override
  String toString() => 'ToolArgumentException: $message';
}

/// 一次工具调用的类型安全参数视图。
class ToolContext {
  const ToolContext(this.call);

  /// 原始调用。
  final ToolCall call;

  /// 解析后的参数对象。
  Map<String, Object?> get arguments => call.arguments;

  /// 调用标识。
  String get callId => call.callId;

  /// 参数是否存在（值可为 null）。
  bool has(String name) => call.arguments.containsKey(name);

  /// 读取原始参数值。
  Object? operator [](String name) => call.arguments[name];

  /// 读取可选参数；不存在返回 `null`，类型不符抛 [ToolArgumentException]。
  T? optional<T>(String name) {
    final Object? value = call.arguments[name];
    if (value == null) return null;
    if (value is T) return value as T;
    throw ToolArgumentException('参数 "$name" 期望 $T，实际 ${value.runtimeType}');
  }

  /// 读取必填参数；缺失、为 null 或类型不符都抛 [ToolArgumentException]。
  T require<T>(String name) {
    if (!call.arguments.containsKey(name)) {
      throw ToolArgumentException('缺少必填参数 "$name"');
    }
    final T? value = optional<T>(name);
    if (value == null) {
      throw ToolArgumentException('参数 "$name" 不能为 null');
    }
    return value;
  }

  /// 可选字符串。
  String? string(String name) => optional<String>(name);

  /// 必填字符串。
  String str(String name) => require<String>(name);

  /// 可选整数。
  int? integer(String name) => optional<int>(name);

  /// 可选数字（整数也接受，统一转 double）。
  double? number(String name) => optional<num>(name)?.toDouble();

  /// 可选布尔。
  bool? boolean(String name) => optional<bool>(name);

  /// 可选数组。
  List<Object?>? array(String name) => optional<List<Object?>>(name);

  /// 可选对象。
  Map<String, Object?>? object(String name) =>
      optional<Map<String, Object?>>(name);
}

/// 工具基类：声明工具的形状并实现执行体。
///
/// [riskLevel] 与 [group] 先予预留（能力分级、分组在更大规模时使用），
/// 默认分别为 [ToolRisk.low] 与不分组。
abstract class Tool {
  const Tool();

  /// 工具名（注册表键）。
  String get name;

  /// 面向模型的简介。
  String get description;

  /// 风险等级；默认只读。
  ToolRisk get riskLevel => ToolRisk.low;

  /// 所属分组；默认不分组。
  String? get group => null;

  /// 参数声明；默认无参数。
  List<ParamSpec> get params => const <ParamSpec>[];

  /// 执行一次调用。
  Future<ToolResult> call(ToolContext context);

  /// 面向模型的白名单投影：只含 `name` / `description` / `parameters`。
  ///
  /// 参数 schema 由 [params] 声明生成；未声明参数时为空对象。
  Map<String, Object?> toSchema() => <String, Object?>{
        'name': name,
        'description': description,
        'parameters': parameterSchema(params),
      };
}
