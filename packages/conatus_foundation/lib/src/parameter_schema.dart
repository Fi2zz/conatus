/// 参数声明 → JSON Schema 编译。
library;

import 'param_spec.dart';

/// 把参数声明列表编译为模型可读的 `type: object` schema。
///
/// 顶层 `required` 聚合声明中标记必填的参数名；无必填项时不输出该字段。
Map<String, Object?> parameterSchema(List<ParamSpec> params) {
  final List<String> required = <String>[
    for (final ParamSpec param in params)
      if (param.required) param.name,
  ];
  return <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      for (final ParamSpec param in params) param.name: param.toJson(),
    },
    if (required.isNotEmpty) 'required': required,
  };
}
