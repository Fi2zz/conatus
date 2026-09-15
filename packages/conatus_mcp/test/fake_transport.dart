/// 测试共用的进程内假传输。
library;

import 'dart:async';
import 'package:conatus_mcp/conatus_mcp.dart';

/// 双向假传输：记录 [sent]、可回灌消息/错误、可模拟对端关闭。
class FakeTransport implements McpTransport {
  final StreamController<McpMessage> _incoming = StreamController<McpMessage>();

  /// 已发出的全部消息（含通知）。
  final List<McpMessage> sent = <McpMessage>[];

  /// 是否连接过。
  bool connected = false;

  /// 是否被断开过。
  bool disconnected = false;

  /// 收到消息时的钩子；用它做自动应答或断言。
  Future<void> Function(McpMessage message)? onSend;

  /// 非空时 [connect] 抛它，模拟连不上的服务端。
  Object? connectError;

  @override
  Stream<McpMessage> get messages => _incoming.stream;

  @override
  Stream<String> get diagnostics => const Stream<String>.empty();

  @override
  Future<void> connect() async {
    final Object? error = connectError;
    if (error != null) throw error;
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
  }

  @override
  Future<void> send(McpMessage message) async {
    sent.add(message);
    final Future<void> Function(McpMessage message)? handler = onSend;
    if (handler != null) await handler(message);
  }

  /// 回灌一条消息。
  void emit(McpMessage message) => _incoming.add(message);

  /// 回灌一个连接级错误。
  void fail(Object error) => _incoming.addError(error);

  /// 结束消息流（模拟对端关闭）。
  Future<void> finish() => _incoming.close();

  /// 已发出的请求（不含通知）。
  List<McpMessage> get requests =>
      sent.where((McpMessage message) => message.request).toList();
}

/// 装上自动应答钩子：[reply] 按方法名算出 `result`（返回 `null` 表示不回应，
/// 用于制造待办请求），并按请求 id 回灌响应。
void autoRespond(
  FakeTransport transport,
  Map<String, Object?>? Function(String method, Map<String, Object?>? params)
      reply,
) {
  transport.onSend = (McpMessage message) async {
    final Object? id = message.id;
    final String? method = message.method;
    if (id == null || method == null) return;
    final Map<String, Object?>? result = reply(method, message.params);
    if (result == null) return;
    transport.emit(McpMessage(id: id, result: result));
  };
}
