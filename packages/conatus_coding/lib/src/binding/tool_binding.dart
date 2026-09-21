/// 绑定桥接：把工具注册表映射为执行环境的绑定命名空间。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import '../runtime/code_run_request.dart';

/// 把 [ToolRegistry] 桥接为绑定命名空间。
///
/// 返回单个 [CodeBindingNamespace]，全局名为 `'tools'`，函数名即工具名，
/// 调用时透传参数并返回工具结果的文本内容。
List<CodeBindingNamespace> toolsAsBindings(ToolRegistry tools) {
  final Map<String, CodeBindingFn> functions = <String, CodeBindingFn>{};
  for (final Map<String, Object?> schema in tools.describe()) {
    final String name = schema['name'] as String;
    functions[name] = (Map<String, Object?> args) async {
      final ToolResult result =
          await tools.call(ToolCall(name: name, arguments: args));
      return result.content;
    };
  }
  return <CodeBindingNamespace>[
    CodeBindingNamespace(global: 'tools', functions: functions),
  ];
}
