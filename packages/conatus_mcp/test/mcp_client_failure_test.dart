import 'dart:async';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';
import 'fake_transport.dart';
import 'mcp_test_support.dart';

void main() {
  test('请求超时：以 timeout 收场', () async {
    final FakeTransport transport = FakeTransport();
    final McpClient client = McpClient(
      transport: transport,
      serverName: 'fake',
      timeout: const Duration(milliseconds: 50),
    );
    addTearDown(client.close);

    final McpException error = await failureOf(
      client.callTool('echo', const <String, Object?>{}),
    );

    expect(error.code, 'timeout');
  });

  test('传输出错：pending 全失败，disconnects 只触发一次', () async {
    final FakeTransport transport = FakeTransport();
    final McpClient client = McpClient(
      transport: transport,
      serverName: 'fake',
      timeout: const Duration(seconds: 5),
    );
    addTearDown(client.close);
    int breaks = 0;
    final Completer<void> broken = Completer<void>();
    final StreamSubscription<void> watch = client.disconnects.listen((_) {
      breaks++;
      if (!broken.isCompleted) broken.complete();
    });
    addTearDown(watch.cancel);

    final Future<McpException> first = failureOf(
      client.callTool('a', const <String, Object?>{}),
    );
    final Future<McpException> second = failureOf(
      client.callTool('b', const <String, Object?>{}),
    );
    transport.fail(const McpException('server-exited', '进程退了'));
    transport.fail(const McpException('server-exited', '又断一次'));

    expect((await first).code, 'disconnected');
    expect((await second).code, 'disconnected');
    await broken.future;
    expect(breaks, 1);
    expect(client.ready, isFalse);

    transport.fail(const McpException('server-exited', '第三次'));
    await pumpEventQueue();
    expect(breaks, 1);
  });

  test('传输结束：pending 全失败并触发 disconnects', () async {
    final FakeTransport transport = FakeTransport();
    final McpClient client = McpClient(
      transport: transport,
      serverName: 'fake',
      timeout: const Duration(seconds: 5),
    );
    addTearDown(client.close);
    final Future<void> broken = client.disconnects.first;

    final Future<McpException> call = failureOf(
      client.callTool('a', const <String, Object?>{}),
    );
    await transport.finish();

    expect((await call).code, 'disconnected');
    await expectLater(broken, completes);
  });

  test('服务端回 error 响应：以 protocol-error 收场', () async {
    final FakeTransport transport = FakeTransport();
    transport.onSend = (McpMessage message) async {
      final Object? id = message.id;
      if (id == null || message.method == null) return;
      transport.emit(
        McpMessage(
          id: id,
          error: const McpError(-32601, '未知方法'),
        ),
      );
    };
    final McpClient client =
        McpClient(transport: transport, serverName: 'fake');
    addTearDown(client.close);

    final McpException error = await failureOf(
      client.callTool('echo', const <String, Object?>{}),
    );

    expect(error.code, 'protocol-error');
    expect(error.message, '-32601: 未知方法');
  });

  test('close：断开传输、幂等、未完成的请求以 closed 失败', () async {
    final FakeTransport transport = FakeTransport();
    final McpClient client = McpClient(
      transport: transport,
      serverName: 'fake',
      timeout: const Duration(seconds: 5),
    );

    final Future<McpException> call = failureOf(
      client.callTool('a', const <String, Object?>{}),
    );
    await client.close();
    await client.close();

    expect(transport.disconnected, isTrue);
    expect((await call).code, 'closed');
  });
}
