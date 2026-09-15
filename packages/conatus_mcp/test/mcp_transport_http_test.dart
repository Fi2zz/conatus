/// `HttpTransport` 的单元测试：用 `MockClient` 假服务端断言请求形态与响应解析。
library;

import 'dart:convert';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'mcp_test_support.dart';

const String _endpoint = 'https://mcp.example.com/mcp';

/// 假 POST 服务端：记录每个请求，按构造时的正文与状态码应答。
class _FakeServer {
  _FakeServer(this.body, {this.status = 200, this.headers = jsonHeaders});

  final String body;
  final int status;
  final Map<String, String> headers;
  final List<http.Request> requests = <http.Request>[];
  late final MockClient client = MockClient(_handle);

  /// 最近一次收到的请求。
  http.Request get last => requests.last;

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    // 用 bytes 构造：`http.Response(String, ...)` 在 content-type 无 charset 时
    // 按 latin1 编码，含中文的 SSE 正文会直接抛错。
    return http.Response.bytes(utf8.encode(body), status, headers: headers);
  }
}

/// 建一个注入假 client 的 `HttpTransport`，并挂上看护与清理。
TransportWatch<HttpTransport> _boot(
  _FakeServer server, {
  Map<String, String> headers = const <String, String>{},
}) {
  final TransportWatch<HttpTransport> watch = TransportWatch<HttpTransport>(
    HttpTransport(url: _endpoint, headers: headers, client: server.client),
  );
  addTearDown(watch.transport.disconnect);
  addTearDown(watch.stop);
  return watch;
}

void main() {
  group('HttpTransport', () {
    test('send：POST 到构造时的 URL，带 JSON 与 SSE 双 Accept', () async {
      final _FakeServer server = _FakeServer(
        jsonRpcResponse(1, <String, Object?>{}),
      );
      final TransportWatch<HttpTransport> watch = _boot(
        server,
        headers: <String, String>{'Authorization': 'Bearer t'},
      );

      await watch.transport.send(
        McpMessage.request(id: 1, method: 'tools/list'),
      );

      expect(server.last.method, 'POST');
      expect(server.last.url.toString(), _endpoint);
      expect(server.last.headers['Content-Type'], 'application/json');
      expect(server.last.headers['Accept'], contains('text/event-stream'));
      expect(server.last.headers['Authorization'], 'Bearer t');
      expect(jsonDecode(server.last.body), <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'tools/list',
        'id': 1,
      });
    });

    test('响应是普通 JSON：单条消息进 messages', () async {
      final _FakeServer server = _FakeServer(
        jsonRpcResponse(1, <String, Object?>{'tools': <Object?>[]}),
      );
      final TransportWatch<HttpTransport> watch = _boot(server);

      await watch.transport.send(
        McpMessage.request(id: 1, method: 'tools/list'),
      );
      await pumpEventQueue();

      expect(watch.messages.single.id, 1);
      expect(
        watch.messages.single.result,
        <String, Object?>{'tools': <Object?>[]},
      );
      expect(watch.failures, isEmpty);
    });

    test('响应是 text/event-stream：逐事件解析，坏载荷只写诊断', () async {
      final String body = <String>[
        ': keep-alive\n\n',
        sseFrame(jsonRpcResponse(1, <String, Object?>{'n': 1})),
        '\n',
        sseFrame(jsonRpcResponse(2, <String, Object?>{'n': 2})),
        sseFrame('{不是 JSON}'),
      ].join();
      final _FakeServer server = _FakeServer(body, headers: sseHeaders);
      final TransportWatch<HttpTransport> watch = _boot(server);
      final List<String> diagnostics = <String>[];
      watch.transport.diagnostics.listen(diagnostics.add);

      await watch.transport.send(
        McpMessage.request(id: 1, method: 'tools/list'),
      );
      await pumpEventQueue();

      expect(watch.messages.map((McpMessage m) => m.id), <Object?>[1, 2]);
      expect(watch.failures, isEmpty);
      expect(diagnostics, hasLength(1));
    });

    test('非 200：抛 http-status，且不当作断连', () async {
      final TransportWatch<HttpTransport> watch =
          _boot(_FakeServer('boom', status: 500));
      await watch.transport.connect();

      await expectLater(
        watch.transport.send(McpMessage.request(id: 1, method: 'tools/list')),
        throwsA(mcpFailure('http-status')),
      );
      await pumpEventQueue();

      expect(watch.messages, isEmpty);
      expect(watch.failures, isEmpty);
    });

    test('disconnect：幂等，且不动调用方传入的 client', () async {
      // `MockClient.close()` 是空操作，没法直接断言「没被关闭」；这里改为钉住
      // 契约：断开可重复调用，且同一个 client 仍能被另一条传输复用
      // （约定见 `McpHttpTransport.closeClient`：自建的才关）。
      final _FakeServer server = _FakeServer(
        jsonRpcResponse(1, <String, Object?>{}),
      );
      final TransportWatch<HttpTransport> watch = _boot(server);

      await watch.transport.connect();
      expect(watch.transport.connected, isTrue);

      await watch.transport.disconnect();
      expect(watch.transport.connected, isFalse);

      await watch.transport.disconnect();
      expect(watch.transport.connected, isFalse);

      final HttpTransport reuse = HttpTransport(
        url: _endpoint,
        client: server.client,
      );
      addTearDown(reuse.disconnect);
      await reuse.send(McpMessage.request(id: 1, method: 'tools/list'));

      expect(server.requests, hasLength(1));
    });
  });
}
