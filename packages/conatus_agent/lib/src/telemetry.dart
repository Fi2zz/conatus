/// telemetry 插件：统一事件导出（可观测性）。
/// 服务键 `'telemetry'`（`ctx.telemetry`）。[Telemetry] 只有 `emit` 与 `events`，
/// 默认 [InMemoryTelemetry]（内存缓冲 + 广播流），[ConsoleTelemetry] 打控制台；
/// 可替换为 OTel / Prometheus 等。埋点用装饰器：[instrumentTools] 挂工具中间件
/// （`tool.called` / `tool.failed`）、[TelemetryLlmProvider] 包模型调用
/// （`llm.request`）、`AgentLoop.onEvent` 产出 `agent.round` / `agent.finished`。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

/// 一条遥测事件。
class TelemetryEvent {
  TelemetryEvent(this.name,
      {this.data = const <String, Object?>{}, DateTime? time})
      : time = time ?? DateTime.now();

  /// 事件名（如 `tool.called` / `llm.request` / `agent.round`）。
  final String name;

  /// 事件负载。
  final Map<String, Object?> data;

  /// 事件时间。
  final DateTime time;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'time': time.toIso8601String(),
        ...data,
      };

  @override
  String toString() => 'TelemetryEvent($name)';
}

/// 遥测导出端口。
abstract class Telemetry {
  /// 记录一条事件。
  void emit(TelemetryEvent event);

  /// 事件流（供评估/监控订阅）。
  Stream<TelemetryEvent> get events;
}

/// 内存导出器：保留最近 [limit] 条并广播。
class InMemoryTelemetry implements Telemetry {
  InMemoryTelemetry({this.limit = 1000}) {
    if (limit < 0) {
      throw ArgumentError.value(limit, 'limit', '必须是非负整数');
    }
  }

  /// 保留条数上限。
  final int limit;

  final List<TelemetryEvent> _recent = <TelemetryEvent>[];
  final StreamController<TelemetryEvent> _controller =
      StreamController<TelemetryEvent>.broadcast();

  /// 最近记录的事件。
  List<TelemetryEvent> get recent => List<TelemetryEvent>.unmodifiable(_recent);

  @override
  Stream<TelemetryEvent> get events => _controller.stream;

  @override
  void emit(TelemetryEvent event) {
    _recent.add(event);
    if (_recent.length > limit) {
      _recent.removeRange(0, _recent.length - limit);
    }
    if (!_controller.isClosed) _controller.add(event);
  }

  /// 关闭广播流。幂等。
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }
}

/// 控制台导出器：`[name] {json}` 一行一条。
class ConsoleTelemetry implements Telemetry {
  ConsoleTelemetry({void Function(String line)? writer})
      : _writer = writer ?? _stdoutWriter;

  final void Function(String line) _writer;

  @override
  Stream<TelemetryEvent> get events => const Stream<TelemetryEvent>.empty();

  @override
  void emit(TelemetryEvent event) =>
      _writer('[${event.name}] ${jsonEncode(event.data)}');

  static void _stdoutWriter(String line) => stdout.writeln(line);
}

/// `ctx.telemetry`：当前上下文可见的遥测导出器。
extension TelemetryContext on Context {
  /// 取当前上下文可见的 [Telemetry]（未提供时抛 [StateError]）。
  Telemetry get telemetry => require<Telemetry>('telemetry');
}

/// 把 [Telemetry] 作为 `'telemetry'` 服务提供到上下文。
Telemetry provideTelemetry(Context ctx, {Telemetry? telemetry}) {
  final Telemetry resolved = telemetry ?? InMemoryTelemetry();
  ctx.provide('telemetry', resolved);
  if (resolved is InMemoryTelemetry) {
    ctx.onDispose(() => unawaited(resolved.close()));
  }
  return resolved;
}

/// 在工具表上挂埋点中间件（`tool.called` / `tool.failed`）。返回撤销函数。
Disposer instrumentTools(Context ctx,
    {Telemetry? telemetry, ToolRegistry? tools}) {
  final Telemetry sink = telemetry ?? ctx.telemetry;
  final ToolRegistry registry = tools ?? ctx.tools;
  return ctx.effect(() => registry.use(
        (ToolCall call, Future<ToolResult> Function() next) async {
          final Stopwatch watch = Stopwatch()..start();
          try {
            final ToolResult result = await next();
            sink.emit(TelemetryEvent('tool.called', data: <String, Object?>{
              'tool': call.name,
              'isError': result.isError,
              'ms': watch.elapsedMilliseconds,
              'args': call.arguments,
            }));
            return result;
          } catch (error) {
            sink.emit(TelemetryEvent('tool.failed', data: <String, Object?>{
              'tool': call.name,
              'ms': watch.elapsedMilliseconds,
              'error': '$error',
            }));
            rethrow;
          }
        },
      ));
}

/// 给任意 [LlmProvider] 加 `llm.request` / `llm.failed` 埋点的装饰器。
class TelemetryLlmProvider implements LlmProvider {
  TelemetryLlmProvider(this.inner, {required this.telemetry});

  /// 被包装的 provider。
  final LlmProvider inner;

  /// 遥测导出器。
  final Telemetry telemetry;

  @override
  String get name => inner.name;

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      final LlmResult result =
          await inner.chat(messages, options: options, tools: tools);
      telemetry.emit(TelemetryEvent('llm.request', data: <String, Object?>{
        'provider': inner.name,
        'model': result.model,
        'ms': watch.elapsedMilliseconds,
        'messages': messages.length,
        'tools': tools?.length ?? 0,
        'toolCalls': result.toolCalls.length,
      }));
      return result;
    } catch (error) {
      telemetry.emit(TelemetryEvent('llm.failed', data: <String, Object?>{
        'provider': inner.name,
        'ms': watch.elapsedMilliseconds,
        'error': '$error',
      }));
      rethrow;
    }
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      inner.chatStream(messages, options: options, tools: tools);

  @override
  void close() => inner.close();
}
