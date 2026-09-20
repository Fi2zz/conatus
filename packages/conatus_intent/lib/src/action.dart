/// 路由动作：三种类型对应三条执行路径。
library;

import 'errors.dart';
import 'route.dart';

/// 路由动作。
sealed class RoutedAction {
  /// 供子类继承。
  const RoutedAction();

  /// 序列化为 JSON。
  ///
  /// 只有声明式构造的动作可序列化：`respond` / `tool` / `delegate`。由代码闭包
  /// 构造的动作（`DirectAction.execute`、`ToolAction.args`）抛
  /// [IntentException]（`not-serializable`）——闭包本来就不是数据。
  Map<String, Object?> toJson();
}

/// 直接返回结果。用于纯本地逻辑，不调用工具。
class DirectAction extends RoutedAction {
  /// 由代码构造：命中后执行 [execute]。
  const DirectAction(this.execute) : text = null;

  /// 静态回复：不依赖上下文，直接返回 [text]。
  const DirectAction.respond(this.text) : execute = null;

  /// 执行体；静态回复动作没有它。
  final Future<Object?> Function(RouteContext ctx)? execute;

  /// 静态回复文本；由代码构造的动作没有它。
  final String? text;

  /// 执行本动作。
  Future<Object?> run(RouteContext ctx) {
    final Future<Object?> Function(RouteContext ctx)? execute = this.execute;
    if (execute != null) return execute(ctx);
    return Future<Object?>.value(text);
  }

  @override
  Map<String, Object?> toJson() {
    final String? text = this.text;
    if (text == null) {
      throw const IntentException('not-serializable', 'DirectAction 由代码构造');
    }
    return <String, Object?>{'type': 'respond', 'text': text};
  }
}

/// 调用工具。用于单工具或简单编排。
class ToolAction extends RoutedAction {
  /// 构造动作。
  const ToolAction({
    required this.tool,
    this.argsTemplate = const <String, Object?>{},
    this.args,
  });

  /// 工具名。
  final String tool;

  /// 声明式参数模板，支持 `{{input}}` / `{{state.<key>}}` 插值。
  final Map<String, Object?> argsTemplate;

  /// 动态参数构造；非空时覆盖 [argsTemplate]。
  final Map<String, Object?> Function(RouteContext ctx)? args;

  /// 解析本次调用的参数。
  Map<String, Object?> resolveArgs(RouteContext ctx) {
    final Map<String, Object?> Function(RouteContext ctx)? args = this.args;
    if (args != null) return args(ctx);
    return interpolateArgs(argsTemplate, ctx);
  }

  @override
  Map<String, Object?> toJson() {
    if (args != null) {
      throw const IntentException('not-serializable', 'ToolAction.args 由代码构造');
    }
    return <String, Object?>{
      'type': 'tool',
      'tool': tool,
      'args': argsTemplate,
    };
  }
}

/// 委托给 Agent Loop。
///
/// 命中后经 `skill` 工具取回技能正文，再由模型据此推理——`conatus_skill` 的设计
/// 口径正是「工具结果由 Agent Loop 正常写进 `tool/result` 事件，因此『模型可见即
/// 已记录』无需额外机制」。用于需要推理或加载指令集的场景。
class DelegateAction extends RoutedAction {
  /// 构造动作。
  const DelegateAction({required this.skill});

  /// 要加载的技能名。
  final String skill;

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'type': 'delegate', 'skill': skill};
}

/// 参数模板插值：字符串里的 `{{input}}` 取原始输入，`{{state.<key>}}` 取上下文状态。
///
/// 解析不出的占位符原样保留，便于排障（而不是静默变成空串）。
Map<String, Object?> interpolateArgs(
  Map<String, Object?> args,
  RouteContext ctx,
) =>
    args.map(
      (String key, Object? value) =>
          MapEntry<String, Object?>(key, _resolve(value, ctx)),
    );

final RegExp _placeholder = RegExp(r'\{\{([^{}]+)\}\}');

Object? _resolve(Object? value, RouteContext ctx) {
  if (value is! String || !value.contains('{{')) return value;
  return value.replaceAllMapped(
    _placeholder,
    (Match match) =>
        _lookup(match.group(1)!.trim(), ctx)?.toString() ?? match.group(0)!,
  );
}

Object? _lookup(String path, RouteContext ctx) {
  if (path == 'input') return ctx.input;
  if (path.startsWith('state.')) return ctx.state[path.substring(6)];
  return null;
}
