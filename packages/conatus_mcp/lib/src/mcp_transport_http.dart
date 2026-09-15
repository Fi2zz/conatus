/// Streamable HTTP 传输：每条消息一次 POST。
library;

import 'mcp_protocol.dart';
import 'mcp_transport_base.dart';

/// 一发一收的 HTTP 传输。
///
/// [send] 把消息 POST 到端点，响应正文既可以是单条 JSON-RPC 响应，也可以是
/// `text/event-stream` 正文（服务端选择流式形态时，正文里可能有多条消息）。
/// 服务端主动推送（没有对应请求的消息）不在此列——需要它就用 [SseTransport]。
///
/// [connect] 不发请求：HTTP 没有需要预先建立的连接，只标记就绪。一个实例
/// 只用一次：[disconnect] 之后 [connected] 为 `false`，不再支持重连。
class HttpTransport extends McpHttpTransport {
  /// 构造。[client] 传入时由调用方负责关闭，否则传输层自建自关。
  HttpTransport({
    required String url,
    super.headers,
    super.client,
  }) : super(url: Uri.parse(url));

  @override
  Future<void> connect() async => markConnected();

  @override
  Future<void> send(McpMessage message) => postJson(url, message);

  @override
  Future<void> disconnect() async {
    markDisconnected();
    closeClient();
    await closeSinks();
  }
}
