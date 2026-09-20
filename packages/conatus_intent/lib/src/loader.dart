/// 从 JSON 加载意图定义。
///
/// 意图是**数据**：`name` / `description` / `patterns` / `examples` / `priority`
/// 加上一个声明式动作。四种动作类型对应 `tool` / `builtin` / `respond` /
/// `delegate`，见 [IntentLoader.buildAction]。
library;

import 'dart:convert';
import 'dart:io';

import 'action.dart';
import 'errors.dart';
import 'intent.dart';
import 'json_helpers.dart';
import 'route.dart';
import 'router.dart';

/// 内置处理器：JSON 里的 `builtin` 动作指向它。
typedef IntentHandler = Future<Object?> Function(RouteContext ctx);

/// 意图配置加载器。
class IntentLoader {
  /// 构造加载器。
  IntentLoader({
    required this.router,
    this.handlers = const <String, IntentHandler>{},
  });

  /// 目标路由器。
  final IntentRouter router;

  /// `builtin` 动作的处理器表。
  final Map<String, IntentHandler> handlers;

  /// 从 JSON 对象加载并逐个注册。
  Future<void> loadFromJson(Map<String, Object?> json) async {
    final Object? items = json['intents'];
    if (items is! List) {
      throw const IntentException('bad-type', '字段类型错误: intents');
    }
    for (final Object? item in items) {
      router.register(parse(_asMap(item, 'intents')));
    }
  }

  /// 从文件加载。
  Future<void> loadFromFile(File file) async =>
      loadFromJson(_asMap(jsonDecode(await file.readAsString()), 'root'));

  /// 解析单条意图定义。
  Intent parse(Map<String, Object?> json) =>
      Intent.fromJson(json, actionBuilder: buildAction);

  /// 解析动作定义；未知类型抛 [IntentException]（`unknown-action`）。
  RoutedAction buildAction(Map<String, Object?> json) {
    final String type = json['type'] as String? ?? '';
    final RoutedAction Function(Map<String, Object?> json)? builder =
        _builders[type];
    if (builder == null) {
      throw IntentException('unknown-action', '未知动作类型: $type');
    }
    return builder(json);
  }

  late final Map<String, RoutedAction Function(Map<String, Object?> json)>
      _builders = <String, RoutedAction Function(Map<String, Object?>)>{
    'tool': _buildTool,
    'builtin': _buildBuiltin,
    'respond': _buildRespond,
    'delegate': _buildDelegate,
  };

  RoutedAction _buildTool(Map<String, Object?> json) => ToolAction(
        tool: requiredString(json, 'tool'),
        argsTemplate: json['args'] == null
            ? const <String, Object?>{}
            : requiredStringMap(json, 'args'),
      );

  RoutedAction _buildBuiltin(Map<String, Object?> json) =>
      DirectAction(_handler(requiredString(json, 'handler')));

  RoutedAction _buildRespond(Map<String, Object?> json) =>
      DirectAction.respond(requiredString(json, 'text'));

  RoutedAction _buildDelegate(Map<String, Object?> json) =>
      DelegateAction(skill: requiredString(json, 'skill'));

  IntentHandler _handler(String name) {
    final IntentHandler? handler = handlers[name];
    if (handler == null) {
      throw IntentException('unknown-handler', '未注册的内置处理器: $name');
    }
    return handler;
  }
}

Map<String, Object?> _asMap(Object? value, String field) {
  if (value is Map) return Map<String, Object?>.from(value);
  throw IntentException('bad-type', '字段类型错误: $field');
}
