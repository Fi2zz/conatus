/// SSE 传输：`GET` 建长连接，服务端先给出 POST 端点。
library;

import 'dart:async';
import 'package:http/http.dart' as http;
import 'mcp_protocol.dart';
import 'mcp_sse.dart';
import 'mcp_transport_base.dart';
import 'mcp_types.dart';

/// `text/event-stream` 长连接 + 一次性 POST 端点的传输。
///
/// [connect] 对端点发 `GET`，服务端会先发一个 `event: endpoint` 事件，其
/// `data` 是（可能相对的）POST 地址；此后的请求走 [send] POST 到该地址，
/// 响应（含服务端主动推送）都从长连接上来。一个实例只用一次：[disconnect]
/// 之后 [connected] 为 `false`，不再支持重连。
class SseTransport extends McpHttpTransport {
  /// 构造。[client] 传入时由调用方负责关闭，否则传输层自建自关。
  SseTransport({
    required String url,
    super.headers,
    super.client,
  }) : super(url: Uri.parse(url));

  StreamSubscription<SseEvent>? _events;
  Uri? _endpoint;

  /// 服务端在 `event: endpoint` 里给出的 POST 地址；握手前为 `null`。
  Uri? get endpoint => _endpoint;

  @override
  Future<void> connect() async {
    final http.StreamedResponse response = await openStream(url);
    markConnected();
    _events = parseSseEvents(response.stream).listen(
      _handleEvent,
      onError: _handleError,
      onDone: _handleDone,
    );
  }

  @override
  Future<void> send(McpMessage message) => postJson(_endpoint ?? url, message);

  @override
  Future<void> disconnect() async {
    await _events?.cancel();
    _events = null;
    markDisconnected();
    closeClient();
    await closeSinks();
  }

  void _handleEvent(SseEvent event) {
    if (event.event == 'endpoint') {
      _endpoint = _resolveEndpoint(event.data);
      return;
    }
    deliverJson(event.data);
  }

  void _handleError(Object error) =>
      emitError(McpException('sse-error', '$error'));

  void _handleDone() =>
      emitError(const McpException('sse-closed', 'SSE 长连接已结束'));

  Uri _resolveEndpoint(String data) {
    final Uri parsed = Uri.parse(data);
    return parsed.isAbsolute ? parsed : url.resolveUri(parsed);
  }
}
