/// 并发装配时的 server 顺序：按 `attach` 调用顺序，不随完成顺序翻转。
library;

import 'dart:async';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

import 'fake_transport.dart';
import 'mcp_test_support.dart';

void main() {
  test('并发 attach：servers 保持调用顺序', () async {
    final Context ctx = Context.root();
    addTearDown(() {
      if (!ctx.disposed) ctx.dispose();
    });
    provideTools(ctx);
    final McpRegistry registry = McpRegistry();
    final Completer<void> slowGate = Completer<void>();

    final FakeTransport slow = FakeTransport();
    autoRespond(slow, fakeServerReply);
    final Future<void> Function(McpMessage) reply = slow.onSend!;
    slow.onSend = (McpMessage message) async {
      if (message.method == 'initialize') await slowGate.future;
      await reply(message);
    };
    final FakeTransport fast = FakeTransport();
    autoRespond(fast, fakeServerReply);

    final Future<void> pending = Future.wait(<Future<void>>[
      registry.attach(ctx, McpClient(transport: slow, serverName: 'first')),
      registry.attach(ctx, McpClient(transport: fast, serverName: 'second')),
    ]);

    // fast 先完成：此刻只有它上账。
    await pumpEventQueue();
    expect(registry.servers, <String>['second']);

    slowGate.complete();
    await pending;
    // 完成顺序是 second → first，但对外顺序按调用顺序。
    expect(registry.servers, <String>['first', 'second']);
  });
}
