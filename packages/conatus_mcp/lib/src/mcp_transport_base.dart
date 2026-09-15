/// HTTP 系传输（`http` / `sse`）的共用实现（内部实现，不对外导出）。
///
/// 负责消息与诊断的收发、坏数据的降级、`http.Client` 的 POST / 长连接
/// 基础设施。子类只声明各自的连接语义与端点：[HttpTransport] 一发一收，
/// [SseTransport] 长连接 + endpoint 事件。
library;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'mcp_json.dart';
import 'mcp_protocol.dart';
import 'mcp_sse.dart';
import 'mcp_transport.dart';
import 'mcp_types.dart';

/// JSON-RPC over HTTP 的公共基类。
///
/// 一个传输实例是**一次性**的：`disconnect` 之后再 `connect` 不会重新建立
/// 可用的会话（消息/诊断控制器已关闭），[connected] 也会复位为 `false`。
abstract class McpHttpTransport implements McpTransport {
  /// 构造。[client] 为空时自建一个，并在 [closeClient] 时关闭它。
  McpHttpTransport({
    required Uri url,
    Map<String, String> headers = const <String, String>{},
    http.Client? client,
  })  : _url = url,
        _headers = headers,
        _client = client ?? http.Client(),
        _owned = client == null;

  final Uri _url;
  final Map<String, String> _headers;
  final http.Client _client;
  final bool _owned;
  final StreamController<McpMessage> _messages = StreamController<McpMessage>();
  final StreamController<String> _diagnostics =
      StreamController<String>.broadcast();
  bool _connected = false;

  /// 传输端点。
  Uri get url => _url;

  /// 连接是否已建立且尚未断开。
  bool get connected => _connected;

  /// 标记连接已建立。
  void markConnected() => _connected = true;

  /// 标记连接已断开。
  ///
  /// `disconnect` 用它复位 [connected]；见类注释：实例一次性，断开后不重连。
  void markDisconnected() => _connected = false;

  @override
  Stream<McpMessage> get messages => _messages.stream;

  @override
  Stream<String> get diagnostics => _diagnostics.stream;

  /// 派发一条消息；控制器已关闭时静默丢弃。
  void emitMessage(McpMessage message) {
    if (_messages.isClosed) return;
    _messages.add(message);
  }

  /// 派发一个连接级错误（如 SSE 中断），上层据此判定断连。
  void emitError(Object error) {
    if (_messages.isClosed) return;
    _messages.addError(error);
  }

  /// 记一条诊断（坏行、状态变化）；诊断不是错误，不打断连接。
  void diagnose(String text) {
    if (_diagnostics.isClosed) return;
    _diagnostics.add(text);
  }

  /// POST 一条 JSON-RPC 消息到 [target]。
  ///
  /// 非 200 抛 [McpException]（`http-status`）而非往 [messages] 灌错误：
  /// 一次 HTTP 失败不该判定整个会话断连，由调用方按次收敛。
  Future<void> postJson(Uri target, McpMessage message) async {
    final http.Response response = await _client.post(
      target,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        ..._headers,
      },
      body: jsonEncode(message.toJson()),
    );
    if (response.statusCode != 200) {
      throw McpException(
        'http-status',
        'MCP POST ${response.statusCode}：${response.body}',
      );
    }
    await deliverPayload(response.body, sse: _eventStream(response));
  }

  /// 对 [target] 发起 `Accept: text/event-stream` 的 GET 长连接。
  ///
  /// 非 200 抛 [McpException]（`http-status`）；返回的响应流由调用方消费。
  Future<http.StreamedResponse> openStream(Uri target) async {
    final http.Request request = http.Request('GET', target)
      ..headers.addAll(<String, String>{
        'Accept': 'text/event-stream',
        ..._headers,
      });
    final http.StreamedResponse response = await _client.send(request);
    if (response.statusCode != 200) {
      throw McpException('http-status', 'MCP SSE ${response.statusCode}');
    }
    return response;
  }

  /// 解析整包正文：[sse] 为真按 SSE 事件逐个解析，否则当单条 JSON。
  Future<void> deliverPayload(String payload, {bool sse = false}) async {
    if (!sse) {
      deliverJson(payload);
      return;
    }
    final Stream<List<int>> bytes =
        Stream<List<int>>.value(utf8.encode(payload));
    await for (final SseEvent event in parseSseEvents(bytes)) {
      deliverJson(event.data);
    }
  }

  /// 解析一条 JSON 载荷；解析不了只写诊断，不打断连接。
  void deliverJson(String payload) {
    final Object? decoded = mcpDecode(payload);
    if (decoded is Map<String, Object?>) {
      emitMessage(McpMessage.fromJson(decoded));
      return;
    }
    diagnose('无法解析的 MCP 载荷：$payload');
  }

  /// 关闭消息与诊断控制器；幂等。
  ///
  /// **不 await** `messages` 的 `done`：单订阅流在没人监听时永远收不到 done
  /// 事件，等它会让 `disconnect` 永久挂起。需要「消息流已结束」这个信号的
  /// 监听方自己等 `done`。
  Future<void> closeSinks() async {
    unawaited(_messages.close());
    unawaited(_diagnostics.close());
  }

  /// 关闭自建的 `http.Client`；调用方传入的 client 由调用方负责。
  void closeClient() {
    if (_owned) _client.close();
  }

  bool _eventStream(http.Response response) =>
      (response.headers['content-type'] ?? '').contains('text/event-stream');
}
