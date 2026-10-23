/// 注册表资源 / prompt 聚合：跨 server 汇总、按 server 过滤、单台失败隔离。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

import 'fake_transport.dart';
import 'mcp_resource_test_support.dart';

void main() {
  late Context ctx;

  setUp(() {
    ctx = Context.root();
    provideTools(ctx);
  });

  tearDown(() {
    if (!ctx.disposed) ctx.dispose();
  });

  test('registry aggregates resources across servers', () async {
    final McpRegistry registry = await bootResourceRegistry(ctx);
    final List<McpResource> resources = await registry.listResources();
    expect(resources.map((McpResource r) => r.uri),
        containsAll(<String>['file:///a', 'file:///b']));
    expect(resources, hasLength(2));
  });

  test('按 server 过滤；未知 server 返回空表', () async {
    final McpRegistry registry = await bootResourceRegistry(ctx);
    final List<McpResource> beta = await registry.listResources(server: 'beta');
    expect(beta.single.uri, 'file:///b');
    expect(await registry.listResources(server: 'missing'), isEmpty);
  });

  test('单台 server 失败返回空，不影响其他 server，并记录原因', () async {
    final McpRegistry registry = await bootResourceRegistry(
      ctx,
      failingServer: 'beta',
      failingMethods: <String>{'resources/list', 'prompts/list'},
    );
    final List<McpResource> resources = await registry.listResources();
    expect(resources.map((McpResource r) => r.uri), <String>['file:///a']);
    expect(registry.lastErrorFor('beta'), contains('boom'));
    expect(registry.lastErrorFor('alpha'), isNull);
    final List<McpPrompt> prompts = await registry.listPrompts();
    expect(prompts.single.name, 'review');
  });

  test('未声明 resources 能力：不发 resources/list', () async {
    final Context other = Context.root();
    addTearDown(other.dispose);
    provideTools(other);
    final FakeTransport transport = fakeServer('bare', declareResources: false);
    final McpRegistry registry = await provideMcp(
      other,
      <McpServerConfig>[
        McpServerConfig(
          name: 'bare',
          type: McpTransportType.stdio,
          command: 'x',
        ),
      ],
      transportFactory: (_) => transport,
    );
    expect(await registry.listResources(), isEmpty);
    expect(
      transport.sent.any((McpMessage m) => m.method == 'resources/list'),
      isFalse,
    );
  });

  test('readResource：文本直出，未知 / 失败 server 返回空', () async {
    final McpRegistry registry = await bootResourceRegistry(ctx);
    final List<McpResourceContents> contents = await registry.readResource(
      server: 'alpha',
      uri: 'file:///a',
    );
    expect(contents.single.text, 'alpha text');
    expect(
      await registry.readResource(server: 'missing', uri: 'file:///a'),
      isEmpty,
    );
    final Context other = Context.root();
    addTearDown(other.dispose);
    provideTools(other);
    final McpRegistry broken = await bootResourceRegistry(
      other,
      failingServer: 'beta',
      failingMethods: <String>{'resources/read'},
    );
    expect(
      await broken.readResource(server: 'beta', uri: 'file:///b'),
      isEmpty,
    );
  });

  test('getPrompt 透传参数并返回消息', () async {
    final McpRegistry registry = await bootResourceRegistry(ctx);
    final List<McpPromptMessage> messages = await registry.getPrompt(
      server: 'alpha',
      name: 'review',
      arguments: <String, String>{'path': 'a.dart', 'depth': '2'},
    );
    expect(messages.single.role, 'user');
    expect(messages.single.text, 'path=a.dart;depth=2');
    expect(
      await registry.getPrompt(server: 'missing', name: 'review'),
      isEmpty,
    );
  });

  test('单台 prompts/get 失败返回空并记录原因', () async {
    final McpRegistry registry = await bootResourceRegistry(
      ctx,
      failingServer: 'alpha',
      failingMethods: <String>{'prompts/get'},
    );
    expect(
      await registry.getPrompt(server: 'alpha', name: 'review'),
      isEmpty,
    );
    expect(registry.lastErrorFor('alpha'), contains('boom'));
  });
}
