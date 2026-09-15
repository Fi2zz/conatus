import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';
import 'fake_transport.dart';
import 'mcp_test_support.dart';

void main() {
  late Context ctx;
  late ToolRegistry tools;
  late FakeMcpServers fakes;

  setUp(() {
    ctx = Context.root();
    tools = provideTools(ctx);
    fakes = FakeMcpServers();
  });

  tearDown(() {
    if (!ctx.disposed) ctx.dispose();
  });

  Future<McpRegistry> boot({
    Map<String, String> aliases = const <String, String>{},
  }) =>
      provideMcp(
        ctx,
        <McpServerConfig>[
          McpServerConfig(
            name: 'fs',
            type: McpTransportType.stdio,
            command: 'npx',
          ),
          McpServerConfig(
            name: 'net',
            type: McpTransportType.http,
            url: 'https://example.com/mcp',
          ),
        ],
        aliases: aliases,
        transportFactory: fakes.build,
      );

  test('装配：工具进 ctx.tools，server 进 ctx.mcp', () async {
    final McpRegistry registry = await boot();

    expect(registry.servers, <String>['fs', 'net']);
    expect(ctx.mcp.servers, <String>['fs', 'net']);
    expect(registry.clientOf('fs')?.ready, isTrue);
    expect(registry.toolsOf('fs').single.name, 'fs__read_file');
    expect(registry.toolsOf('net').single.group, 'mcp:net');
    expect(tools.names, <String>['fs__read_file', 'net__read_file']);
    expect(tools.get('fs__read_file')?.description, 'fs 的 read_file');
    expect(fakes.transports['fs']?.connected, isTrue);
    expect(registry.clientOf('missing'), isNull);
  });

  test('装配后可直接调用服务端工具', () async {
    await boot();

    final ToolResult result = await ctx.tools.call(
      const ToolCall(
        name: 'net__read_file',
        arguments: <String, Object?>{'path': '/a'},
      ),
    );

    expect(result.isError, isFalse);
    expect(result.content, 'net:ok');
    expect(
      fakes.transports['net']?.requests.last.params?['arguments'],
      <String, Object?>{'path': '/a'},
    );
  });

  test('别名：短名指向全名，schema 里的 name 也是短名', () async {
    await boot(aliases: <String, String>{'read_file': 'fs__read_file'});

    expect(tools.get('read_file')?.group, 'mcp:fs');
    expect(tools.get('read_file')?.toSchema()['name'], 'read_file');
    expect(tools.names.contains('fs__read_file'), isTrue);
  });

  test('别名：目标不存在抛 StateError', () async {
    await expectLater(
      boot(aliases: <String, String>{'nope': 'fs__missing'}),
      throwsA(isA<StateError>()),
    );
  });

  test('别名：短名撞车抛 StateError', () async {
    await expectLater(
      boot(aliases: <String, String>{'fs__read_file': 'net__read_file'}),
      throwsA(isA<StateError>()),
    );
  });

  test('某 server 断连：只注销它的工具，其余照常', () async {
    await boot();

    await fakes.transports['fs']!.finish();
    await pumpEventQueue();

    expect(tools.names, <String>['net__read_file']);
    expect(ctx.mcp.servers, <String>['net']);
    expect(ctx.mcp.clientOf('fs'), isNull);
    final ToolResult result = await ctx.tools.call(
      const ToolCall(name: 'net__read_file'),
    );
    expect(result.content, 'net:ok');
  });

  test('ctx.dispose：断开全部连接并注销工具', () async {
    await boot();

    ctx.dispose();
    await pumpEventQueue();

    expect(fakes.transports['fs']?.disconnected, isTrue);
    expect(fakes.transports['net']?.disconnected, isTrue);
    expect(tools.names, isEmpty);
  });

  test('装配失败：断开该客户端、不上账、不注册工具', () async {
    final FakeTransport broken = FakeTransport()
      ..connectError = const McpException('not-connected', '连不上');

    await expectLater(
      provideMcp(
        ctx,
        <McpServerConfig>[
          McpServerConfig(
            name: 'fs',
            type: McpTransportType.stdio,
            command: 'npx',
          ),
        ],
        transportFactory: (McpServerConfig config) => broken,
      ),
      throwsA(isA<McpException>()),
    );

    expect(broken.disconnected, isTrue);
    expect(ctx.mcp.servers, isEmpty);
    expect(tools.names, isEmpty);
  });
}
