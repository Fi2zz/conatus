/// `ctx.tools.fn(...)`：一行注册简单工具。
///
/// 用 [ToolFn.fn] 把「名字 + 说明 + 参数声明 + 处理函数」直接登记进注册表，
/// 省去为小工具单独建类；内部仍以 [_FnTool] 走同一条注册与执行管线，因此参数
/// 校验、超时、异常收敛与 `onChange`/`onResult` 全部生效。
///
/// ```dart
/// ctx.effect(() => ctx.tools.fn(
///   'echo',
///   description: '回显输入',
///   params: <ParamSpec>[ParamSpec.string('text', required: true)],
///   handler: (ctx) async => ToolResult.success(ctx.str('text')),
/// ));
/// ```
library;

import 'package:conatus_core/conatus_core.dart';
import 'tools.dart';

/// 便捷注册扩展。
extension ToolFn on ToolRegistry {
  /// 注册一个由 [handler] 驱动的工具，返回撤销函数（幂等）。
  Disposer fn(
    String name, {
    String description = '',
    List<ParamSpec> params = const <ParamSpec>[],
    ToolRisk riskLevel = ToolRisk.low,
    String? group,
    required Future<ToolResult> Function(ToolContext context) handler,
  }) =>
      register(_FnTool(
        name: name,
        description: description,
        params: params,
        riskLevel: riskLevel,
        group: group,
        handler: handler,
      ));
}

/// [ToolFn.fn] 背后的工具实现。
class _FnTool extends Tool {
  const _FnTool({
    required this.name,
    required this.description,
    required this.params,
    required this.riskLevel,
    required this.group,
    required this.handler,
  });

  @override
  final String name;

  @override
  final String description;

  @override
  final List<ParamSpec> params;

  @override
  final ToolRisk riskLevel;

  @override
  final String? group;

  final Future<ToolResult> Function(ToolContext context) handler;

  @override
  Future<ToolResult> call(ToolContext context) => handler(context);
}
