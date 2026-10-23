/// `HttpTransport` 的 OAuth 鉴权：每次请求带 Bearer，401 刷新一次并重试。
library;

import 'dart:convert';

import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'mcp_test_support.dart';

const String _endpoint = 'https://mcp.example.com/mcp';

/// 按预设状态码序列应答的假服务端。
class _AuthServer {
  _AuthServer(this.statuses);

  final List<int> statuses;
  final List<http.Request> requests = <http.Request>[];

  late final MockClient client = MockClient((http.Request request) async {
    requests.add(request);
    final int status = statuses[requests.length <= statuses.length
        ? requests.length - 1
        : statuses.length - 1];
    if (status != 200) return http.Response('unauthorized', status);
    return http.Response.bytes(
      utf8.encode(jsonRpcResponse(1, <String, Object?>{})),
      200,
      headers: jsonHeaders,
    );
  });
}

Matcher _failure(String code) => throwsA(
      isA<McpException>().having((McpException e) => e.code, 'code', code),
    );

void main() {
  test('authHeaders 合并进请求；200 时不刷新', () async {
    final _AuthServer server = _AuthServer(<int>[200]);
    int refreshes = 0;
    final HttpTransport transport = HttpTransport(
      url: _endpoint,
      client: server.client,
      authHeaders: () async =>
          <String, String>{'Authorization': 'Bearer access-1'},
      refreshAuth: () async {
        refreshes++;
        return <String, String>{'Authorization': 'Bearer access-2'};
      },
    );
    addTearDown(transport.disconnect);

    await transport.send(McpMessage.request(id: 1, method: 'tools/list'));

    expect(server.requests.single.headers['Authorization'], 'Bearer access-1');
    expect(refreshes, 0);
  });

  test('401：刷新一次并带新头重试', () async {
    final _AuthServer server = _AuthServer(<int>[401, 200]);
    final HttpTransport transport = HttpTransport(
      url: _endpoint,
      client: server.client,
      authHeaders: () async => <String, String>{'Authorization': 'Bearer old'},
      refreshAuth: () async => <String, String>{'Authorization': 'Bearer new'},
    );
    addTearDown(transport.disconnect);

    await transport.send(McpMessage.request(id: 1, method: 'tools/list'));

    expect(server.requests, hasLength(2));
    expect(server.requests.first.headers['Authorization'], 'Bearer old');
    expect(server.requests.last.headers['Authorization'], 'Bearer new');
  });

  test('刷新后仍 401：只重试一次，收敛为 needs_auth', () async {
    final _AuthServer server = _AuthServer(<int>[401, 401]);
    int refreshes = 0;
    final HttpTransport transport = HttpTransport(
      url: _endpoint,
      client: server.client,
      authHeaders: () async => <String, String>{'Authorization': 'Bearer old'},
      refreshAuth: () async {
        refreshes++;
        return <String, String>{'Authorization': 'Bearer new'};
      },
    );
    addTearDown(transport.disconnect);

    await expectLater(
      transport.send(McpMessage.request(id: 1, method: 'tools/list')),
      _failure('needs_auth'),
    );

    expect(refreshes, 1);
    expect(server.requests, hasLength(2));
  });

  test('没有 refreshAuth：401 直接 needs_auth', () async {
    final _AuthServer server = _AuthServer(<int>[401]);
    final HttpTransport transport = HttpTransport(
      url: _endpoint,
      client: server.client,
      authHeaders: () async => <String, String>{'Authorization': 'Bearer old'},
    );
    addTearDown(transport.disconnect);

    await expectLater(
      transport.send(McpMessage.request(id: 1, method: 'tools/list')),
      _failure('needs_auth'),
    );
    expect(server.requests, hasLength(1));
  });

  test('刷新抛错收敛成 needs_auth，不透传原始异常', () async {
    final _AuthServer server = _AuthServer(<int>[401]);
    final HttpTransport transport = HttpTransport(
      url: _endpoint,
      client: server.client,
      authHeaders: () async => <String, String>{'Authorization': 'Bearer old'},
      refreshAuth: () async => throw StateError('refresh-secret-token'),
    );
    addTearDown(transport.disconnect);

    await expectLater(
      transport.send(McpMessage.request(id: 1, method: 'tools/list')),
      throwsA(
        isA<McpException>()
            .having((McpException e) => e.code, 'code', 'needs_auth')
            .having((McpException e) => e.message, 'message',
                isNot(contains('refresh-secret-token'))),
      ),
    );
    expect(server.requests, hasLength(1));
  });

  test('非 401 的失败仍是 http-status', () async {
    final _AuthServer server = _AuthServer(<int>[500]);
    final HttpTransport transport = HttpTransport(
      url: _endpoint,
      client: server.client,
      authHeaders: () async => <String, String>{'Authorization': 'Bearer old'},
    );
    addTearDown(transport.disconnect);

    await expectLater(
      transport.send(McpMessage.request(id: 1, method: 'tools/list')),
      _failure('http-status'),
    );
  });
}
