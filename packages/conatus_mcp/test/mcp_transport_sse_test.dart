/// `SseTransport` 的单元测试：用 `MockClient.streaming` 假 SSE 服务端
/// （`GET` 返回可推送的长连接，`POST` 走 `event: endpoint` 给出的地址）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'mcp_test_support.dart';

const String _streamUrl = 'http://localhost:8080/sse';
final Uri _postUrl = Uri.parse('http://localhost:8080/messages?session=1');

/// 假 SSE 服务端：`GET` 返回长连接，`POST` 记录请求并可经长连接回推响应。
///
/// POST 的应答是**空**的 `text/event-stream`（真实 SSE server 的常见形态），
/// 因此响应只能从长连接上来——正好检验端到端链路。
class _FakeSseServer {
  final StreamController<List<int>> _stream = StreamController<List<int>>();
  final List<http.BaseRequest> requests = <http.BaseRequest>[];
  final List<String> posts = <String>[];

  /// 收到 POST 时的钩子；用它把 JSON-RPC 响应推回长连接。
  void Function(McpMessage message)? onPost;

  late final MockClient client = MockClient.streaming(_handle);

  /// `GET` 收到的请求（长连接的建立）。
  http.BaseRequest get get => requests
      .firstWhere((http.BaseRequest request) => request.method == 'GET');

  /// 最近一次收到的请求。
  http.BaseRequest get last => requests.last;

  /// 往长连接推一段字节。
  void push(String text) => _stream.add(utf8.encode(text));

  /// 往长连接注入一个错误（模拟网络中断）。
  void fail(Object error) => _stream.addError(error);

  /// 关闭长连接。
  Future<void> closeStream() => _stream.close();

  Future<http.StreamedResponse> _handle(
    http.BaseRequest request,
    http.ByteStream body,
  ) async {
    requests.add(request);
    if (request.method == 'GET') {
      return http.StreamedResponse(_stream.stream, 200, headers: sseHeaders);
    }
    final String payload = utf8.decode(await body.toBytes());
    posts.add(payload);
    final Object? decoded = jsonDecode(payload);
    if (decoded is Map<String, Object?>) {
      onPost?.call(McpMessage.fromJson(decoded));
    }
    return http.StreamedResponse(
      const Stream<List<int>>.empty(),
      200,
      headers: sseHeaders,
    );
  }
}

/// 建一个注入假 client 的 `SseTransport`，并挂上看护与清理。
TransportWatch<SseTransport> _boot(_FakeSseServer server) {
  final TransportWatch<SseTransport> watch = TransportWatch<SseTransport>(
    SseTransport(url: _streamUrl, client: server.client),
  );
  addTearDown(watch.transport.disconnect);
  addTearDown(watch.stop);
  addTearDown(server.closeStream);
  return watch;
}

void main() {
  test('connect：GET 长连接，Accept 是 text/event-stream', () async {
    final _FakeSseServer server = _FakeSseServer();
    final TransportWatch<SseTransport> watch = _boot(server);

    await watch.transport.connect();

    expect(server.get.method, 'GET');
    expect(server.get.url.toString(), _streamUrl);
    expect(server.get.headers['Accept'], 'text/event-stream');
    expect(watch.transport.connected, isTrue);
    expect(watch.transport.endpoint, isNull);
  });

  test('endpoint 事件：相对地址按基址解析，send POST 到它', () async {
    final _FakeSseServer server = _FakeSseServer();
    final TransportWatch<SseTransport> watch = _boot(server);
    await watch.transport.connect();

    server.push(sseFrame('/messages?session=1', event: 'endpoint'));
    await pumpEventQueue();

    expect(watch.transport.endpoint, _postUrl);

    await watch.transport.send(McpMessage.request(id: 1, method: 'tools/list'));

    expect(server.last.method, 'POST');
    expect(server.last.url, _postUrl);
    expect(server.posts.single, contains('"tools/list"'));
  });

  test('全程：响应经 SSE 长连接回推，McpClient 拿得到', () async {
    // 这里不用 _boot：`messages` 是单订阅流，McpClient 必须是唯一的听者。
    final _FakeSseServer server = _FakeSseServer();
    final SseTransport transport = SseTransport(
      url: _streamUrl,
      client: server.client,
    );
    addTearDown(transport.disconnect);
    addTearDown(server.closeStream);
    final McpClient client = McpClient(transport: transport, serverName: 'sse');
    addTearDown(client.close);
    server.onPost = (McpMessage message) {
      final Object? id = message.id;
      if (id == null) return; // 通知不用回应
      final Map<String, Object?> result = message.method == 'initialize'
          ? <String, Object?>{
              'protocolVersion': kMcpProtocolVersion,
              'serverInfo': <String, Object?>{'name': 'sse', 'version': '1.0'},
            }
          : <String, Object?>{
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': 'via-sse'},
              ],
            };
      server.push(sseFrame(jsonRpcResponse(id, result)));
    };
    server.push(sseFrame('/messages?session=1', event: 'endpoint'));

    final McpServerInfo info = await client.initialize();
    await pumpEventQueue();

    expect(info.name, 'sse');
    expect(transport.endpoint, _postUrl);

    final McpToolResult result =
        await client.callTool('echo', const <String, Object?>{});

    expect(describeMcpContent(result.content), 'via-sse');
    expect(server.last.url, _postUrl);
    expect(server.posts.last, contains('"tools/call"'));
  });

  test('长连接结束：messages 收到 sse-closed 错误', () async {
    final _FakeSseServer server = _FakeSseServer();
    final TransportWatch<SseTransport> watch = _boot(server);
    await watch.transport.connect();

    await server.closeStream();
    await pumpEventQueue();

    expect(watch.failures, hasLength(1));
    expect((watch.failures.single as McpException).code, 'sse-closed');
  });

  test('长连接出错：messages 收到 sse-error 错误', () async {
    final _FakeSseServer server = _FakeSseServer();
    final TransportWatch<SseTransport> watch = _boot(server);
    await watch.transport.connect();

    server.fail(const SocketException('断了'));
    await pumpEventQueue();

    expect(watch.failures, hasLength(1));
    expect((watch.failures.single as McpException).code, 'sse-error');
  });

  test('disconnect：取消订阅、关闭 messages 流，且幂等', () async {
    final _FakeSseServer server = _FakeSseServer();
    final TransportWatch<SseTransport> watch = _boot(server);

    await watch.transport.connect();
    expect(watch.transport.connected, isTrue);
    server.push(sseFrame(jsonRpcResponse(1, <String, Object?>{})));
    await pumpEventQueue();
    expect(watch.messages, hasLength(1));

    await watch.transport.disconnect();
    await watch.transport.disconnect();
    expect(watch.transport.connected, isFalse);
    await watch.closed.future;

    server.push(sseFrame(jsonRpcResponse(2, <String, Object?>{})));
    await pumpEventQueue();
    expect(watch.messages, hasLength(1));
  });
}
