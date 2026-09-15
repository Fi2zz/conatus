/// 工具参数声明与 JSON Schema 生成。
///
/// 作者用 [ParamSpec] 声明参数（string / integer / number / boolean / enum /
/// array / object），[parameterSchema] 把声明列表编译成模型可读的
/// `type: object` schema；[Tool.toSchema] 直接消费它，作者不再手写 schema。
library;

/// 参数类型。
enum ParamType { string, integer, number, boolean, enumeration, array, object }

/// 一个参数的声明。
///
/// 简单类型用对应的工厂构造（[ParamSpec.string] / [ParamSpec.integer] /
/// [ParamSpec.number] / [ParamSpec.boolean]）；枚举用 [ParamSpec.enumeration]；
/// 数组用 [ParamSpec.array]（带 [items]）；对象用 [ParamSpec.object]（带
/// [properties]，其嵌套 `required` 由子声明聚合）。
class ParamSpec {
  const ParamSpec({
    required this.name,
    required this.type,
    this.description,
    this.required = false,
    this.enumValues = const <String>[],
    this.items,
    this.properties = const <String, ParamSpec>{},
    this.defaultValue,
  });

  /// 字符串参数。
  factory ParamSpec.string(
    String name, {
    String? description,
    bool required = false,
    String? defaultValue,
  }) =>
      ParamSpec(
        name: name,
        type: ParamType.string,
        description: description,
        required: required,
        defaultValue: defaultValue,
      );

  /// 整数参数。
  factory ParamSpec.integer(
    String name, {
    String? description,
    bool required = false,
    int? defaultValue,
  }) =>
      ParamSpec(
        name: name,
        type: ParamType.integer,
        description: description,
        required: required,
        defaultValue: defaultValue,
      );

  /// 数字参数（整数或小数）。
  factory ParamSpec.number(
    String name, {
    String? description,
    bool required = false,
    num? defaultValue,
  }) =>
      ParamSpec(
        name: name,
        type: ParamType.number,
        description: description,
        required: required,
        defaultValue: defaultValue,
      );

  /// 布尔参数。
  factory ParamSpec.boolean(
    String name, {
    String? description,
    bool required = false,
    bool? defaultValue,
  }) =>
      ParamSpec(
        name: name,
        type: ParamType.boolean,
        description: description,
        required: required,
        defaultValue: defaultValue,
      );

  /// 字符串枚举参数。[values] 不能为空。
  factory ParamSpec.enumeration(
    String name,
    List<String> values, {
    String? description,
    bool required = false,
    String? defaultValue,
  }) {
    if (values.isEmpty) {
      throw ArgumentError.value(values, 'values', '枚举取值不能为空');
    }
    return ParamSpec(
      name: name,
      type: ParamType.enumeration,
      description: description,
      required: required,
      enumValues: List<String>.unmodifiable(values),
      defaultValue: defaultValue,
    );
  }

  /// 数组参数。[items] 声明元素类型。
  factory ParamSpec.array(
    String name, {
    required ParamSpec items,
    String? description,
    bool required = false,
  }) =>
      ParamSpec(
        name: name,
        type: ParamType.array,
        description: description,
        required: required,
        items: items,
      );

  /// 对象参数。[properties] 声明嵌套字段。
  factory ParamSpec.object(
    String name, {
    required Map<String, ParamSpec> properties,
    String? description,
    bool required = false,
  }) =>
      ParamSpec(
        name: name,
        type: ParamType.object,
        description: description,
        required: required,
        properties: Map<String, ParamSpec>.unmodifiable(properties),
      );

  /// 参数名。
  final String name;

  /// 参数类型。
  final ParamType type;

  /// 面向模型的说明。
  final String? description;

  /// 是否必填。
  final bool required;

  /// 枚举取值（仅 [ParamType.enumeration]）。
  final List<String> enumValues;

  /// 元素声明（仅 [ParamType.array]）。
  final ParamSpec? items;

  /// 嵌套字段（仅 [ParamType.object]）。
  final Map<String, ParamSpec> properties;

  /// 默认值（作为 schema 注解，不参与校验）。
  final Object? defaultValue;

  /// 编译为单个 JSON Schema 片段。
  Map<String, Object?> toJson() => <String, Object?>{
        'type': _typeName(),
        if (type == ParamType.enumeration) 'enum': enumValues,
        if (type == ParamType.array && items != null) 'items': items!.toJson(),
        if (type == ParamType.object)
          'properties': <String, Object?>{
            for (final MapEntry<String, ParamSpec> entry in properties.entries)
              entry.key: entry.value.toJson(),
          },
        if (_requiredProperties().isNotEmpty) 'required': _requiredProperties(),
        if (description != null) 'description': description,
        if (defaultValue != null) 'default': defaultValue,
      };

  List<String> _requiredProperties() => <String>[
        for (final MapEntry<String, ParamSpec> entry in properties.entries)
          if (entry.value.required) entry.key,
      ];

  String _typeName() => switch (type) {
        ParamType.string => 'string',
        ParamType.integer => 'integer',
        ParamType.number => 'number',
        ParamType.boolean => 'boolean',
        ParamType.enumeration => 'string',
        ParamType.array => 'array',
        ParamType.object => 'object',
      };
}
