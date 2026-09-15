/// tools 插件：工具注册表 + 受控执行管线。
///
/// 服务键 `'tools'`。注册的工具面向模型暴露白名单 schema（`name` /
/// `description` / `parameters`，执行体等宿主字段永不外泄）；[ToolRegistry.call]
/// 先按 [Tool.params] 校验参数，再依次经过单调守卫（guard）与环绕中间件
/// （middleware），最后调用工具执行体并广播 [ToolRegistry.onResult]。参数不合法、
/// 超时、未知工具与执行体异常都被收敛为失败结果，不向外传播。所有登记返回
/// [Disposer]，交给 `ctx.effect(...)` 即可随上下文卸载自动撤销；[ToolsContext.tools]
/// 提供 `ctx.tools` 快捷访问。
///
/// ```dart
/// final tools = provideTools(app);
/// app.plugin('echo', (ctx) => ctx.effect(() => tools.register(const EchoTool())));
/// await ctx.tools.call(const ToolCall(name: 'echo', arguments: {'text': 'hi'}));
/// ```
library;

import 'package:conatus_core/conatus_core.dart';
import 'tool.dart';
import 'tool_types.dart';
import 'tool_validation.dart';

export 'param_spec.dart';
export 'parameter_schema.dart';
export 'tool.dart';
export 'tool_types.dart';

/// 工具注册表与执行管线。
class ToolRegistry {
  ToolRegistry({this.defaultTimeout});

  /// [call] 未传 `timeout` 时使用的默认超时；null 表示不限时。
  Duration? defaultTimeout;

  final Map<String, Tool> _tools = <String, Tool>{};
  final List<ToolGuard> _guards = <ToolGuard>[];
  final List<ToolMiddleware> _middlewares = <ToolMiddleware>[];
  final List<void Function()> _changeListeners = <void Function()>[];
  final List<ToolResultListener> _resultListeners = <ToolResultListener>[];

  /// 已注册的工具名（按注册顺序）。
  List<String> get names => _tools.keys.toList(growable: false);

  /// 已注册的工具数。
  int get length => _tools.length;

  /// 查找工具；未注册返回 `null`。
  Tool? get(String name) => _tools[name];

  /// 注册一个工具。同名重复注册抛 [StateError]；返回撤销函数（幂等）。
  Disposer register(Tool tool) {
    if (_tools.containsKey(tool.name)) {
      throw StateError('工具 "${tool.name}" 已注册');
    }
    _tools[tool.name] = tool;
    _notifyChange();
    bool removed = false;
    return () {
      if (removed) return;
      removed = true;
      if (identical(_tools[tool.name], tool)) {
        _tools.remove(tool.name);
        _notifyChange();
      }
    };
  }

  /// 当前可见工具的模型 schema 列表（白名单投影）。
  List<Map<String, Object?>> describe() =>
      <Map<String, Object?>>[for (final Tool t in _tools.values) t.toSchema()];

  /// 按名描述单个工具；未注册返回 `null`。
  Map<String, Object?>? describeOne(String name) => _tools[name]?.toSchema();

  /// 登记一个单调守卫。返回撤销函数（幂等）。
  Disposer guard(ToolGuard guard) {
    _guards.add(guard);
    return () => _guards.remove(guard);
  }

  /// 登记一个环绕中间件（后进先出包裹执行体）。返回撤销函数（幂等）。
  Disposer use(ToolMiddleware middleware) {
    _middlewares.add(middleware);
    return () => _middlewares.remove(middleware);
  }

  /// 监听工具表变更。返回撤销函数（幂等）。
  Disposer onChange(void Function() listener) {
    _changeListeners.add(listener);
    return () => _changeListeners.remove(listener);
  }

  /// 监听每次调用结局。返回撤销函数（幂等）。
  Disposer onResult(ToolResultListener listener) {
    _resultListeners.add(listener);
    return () => _resultListeners.remove(listener);
  }

  /// 调用一个工具：校验参数 → 守卫 → 中间件链 → 执行体 → 广播结果。
  ///
  /// [timeout] 覆盖 [defaultTimeout]。参数不合法（`INVALID_ARGS`）、超时
  /// （`TOOL_TIMEOUT`）、未知工具（`UNKNOWN_TOOL`）、守卫拒绝（`TOOL_DENIED`）
  /// 与执行体异常（`TOOL_ERROR`）都返回失败结果而非抛出。
  Future<ToolResult> call(ToolCall call, {Duration? timeout}) async {
    final ToolResult result = await _dispatch(call, timeout);
    for (final ToolResultListener listener
        in List<ToolResultListener>.of(_resultListeners)) {
      listener(call, result);
    }
    return result;
  }

  Future<ToolResult> _dispatch(ToolCall call, Duration? timeout) async {
    final Tool? tool = _tools[call.name];
    if (tool == null) {
      return ToolResult.failure(
        '未知工具 "${call.name}"',
        error: ToolError('UNKNOWN_TOOL', 'unknown tool "${call.name}"'),
      );
    }
    final List<String> violations = validateToolArgs(tool, call.arguments);
    if (violations.isNotEmpty) {
      return ToolResult.failure(
        '参数不合法：${violations.join('；')}',
        error: ToolError('INVALID_ARGS', violations.join('; ')),
      );
    }
    for (final ToolGuard guard in List<ToolGuard>.of(_guards)) {
      final String? denial = guard(call);
      if (denial != null) {
        return ToolResult.failure(
          denial,
          error: ToolError('TOOL_DENIED', denial),
        );
      }
    }
    final Duration? effective = timeout ?? defaultTimeout;
    try {
      final Future<ToolResult> execution = _chain(tool, call)();
      return await _withTimeout(call, execution, effective);
    } catch (error) {
      return ToolResult.failure(
        '$error',
        error: ToolError('TOOL_ERROR', '$error'),
      );
    }
  }

  Future<ToolResult> _withTimeout(
    ToolCall call,
    Future<ToolResult> execution,
    Duration? timeout,
  ) {
    if (timeout == null) return execution;
    return execution.timeout(
      timeout,
      onTimeout: () => ToolResult.failure(
        '工具 "${call.name}" 超时（${timeout.inMilliseconds}ms）',
        error: ToolError('TOOL_TIMEOUT', '${call.name} timed out'),
      ),
    );
  }

  Future<ToolResult> Function() _chain(Tool tool, ToolCall call) {
    Future<ToolResult> body() => tool.call(ToolContext(call));
    Future<ToolResult> Function() chain = body;
    for (final ToolMiddleware middleware in _middlewares.reversed) {
      final Future<ToolResult> Function() next = chain;
      chain = () => middleware(call, next);
    }
    return chain;
  }

  void _notifyChange() {
    for (final void Function() listener
        in List<void Function()>.of(_changeListeners)) {
      listener();
    }
  }
}

/// `ctx.tools`：当前上下文可见的工具注册表。
extension ToolsContext on Context {
  /// 取当前上下文可见的 [ToolRegistry]（未提供时抛 [StateError]）。
  ToolRegistry get tools => require<ToolRegistry>('tools');
}

/// 将 [ToolRegistry] 作为 `'tools'` 服务提供到上下文。
ToolRegistry provideTools(
  Context ctx, {
  ToolRegistry? tools,
  Duration? timeout,
}) {
  final ToolRegistry registry = tools ?? ToolRegistry(defaultTimeout: timeout);
  ctx.provide('tools', registry);
  return registry;
}
