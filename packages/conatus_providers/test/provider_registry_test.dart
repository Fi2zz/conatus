/// 提供商注册表：增删改查、持久化与 LlmProvider 构造。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_providers/conatus_providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// 固定返回 [body] JSON 的假 client。
MockClient _jsonClient(Object? body) =>
    MockClient((http.Request request) async => http.Response(jsonEncode(body), 200));

void main() {
  late Directory dir;
  late String path;
  late ProviderStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('providers-test-');
    path = '${dir.path}/providers.json';
    store = ProviderStore(path: path);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  ProviderProfile profile(String name, {String? model}) => ProviderProfile(
        name: name,
        baseUrl: 'https://$name.example/v1',
        credentialKey: '${name.toUpperCase()}_API_KEY',
        models: <String>[model ?? '$name-model'],
      );

  test('首次 load 落盘内置默认并选中首个', () async {
    final ProviderRegistry registry = ProviderRegistry(
      store: store,
      builtin: <ProviderProfile>[profile('a'), profile('b')],
    );

    await registry.load();

    expect(registry.profiles.map((ProviderProfile p) => p.name),
        <String>['a', 'b']);
    expect(registry.currentName, 'a');
    expect(File(path).existsSync(), isTrue);
  });

  test('增删改查与持久化往返', () async {
    final ProviderRegistry registry = ProviderRegistry(
      store: store,
      builtin: <ProviderProfile>[profile('a')],
    );
    await registry.load();
    await registry.add(profile('b'), select: true);
    expect(registry.currentName, 'b');

    final ProviderRegistry reloaded = ProviderRegistry(store: store);
    await reloaded.load();
    expect(reloaded.profiles.map((ProviderProfile p) => p.name),
        <String>['a', 'b']);
    expect(reloaded.currentName, 'b');

    await reloaded.remove('b');
    expect(reloaded.profiles.map((ProviderProfile p) => p.name), <String>['a']);
    expect(reloaded.currentName, 'a');
  });

  test('同名 add 覆盖，select 未知名字返回 false', () async {
    final ProviderRegistry registry = ProviderRegistry(
      store: store,
      builtin: <ProviderProfile>[profile('a')],
    );
    await registry.load();

    await registry.add(profile('a', model: 'a2'));

    expect(registry.profiles, hasLength(1));
    expect(registry.profiles.single.defaultModel, 'a2');
    expect(await registry.select('nope'), isFalse);
  });

  test('buildLlm 按 profile 构造，缺 provider / 模型名返回 null', () async {
    final ProviderRegistry registry = ProviderRegistry(
      store: store,
      builtin: <ProviderProfile>[profile('a')],
    );
    await registry.load();

    final LlmProvider? llm = registry.buildLlm('a');
    expect(llm, isNotNull);
    expect(llm!.name, 'a');
    expect(registry.buildLlm('a', model: 'x'), isNotNull);
    expect(registry.buildLlm('nope'), isNull);

    await registry.add(const ProviderProfile(name: 'empty', baseUrl: 'https://e'));
    expect(registry.buildLlm('empty'), isNull);
  });

  test('损坏文件回落并重建内置默认', () async {
    File(path).writeAsStringSync('{ not json');

    final ProviderRegistry registry = ProviderRegistry(
      store: store,
      builtin: <ProviderProfile>[profile('a')],
    );
    await registry.load();

    expect(registry.profiles.map((ProviderProfile p) => p.name), <String>['a']);
  });

  test('内置默认：两个 Plan 提供商带文档模型清单', () {
    final ProviderProfile coding = kDefaultProviders
        .firstWhere((ProviderProfile p) => p.name == 'volcengine-coding-plan');
    expect(coding.baseUrl, 'https://ark.cn-beijing.volces.com/api/coding/v3');
    expect(coding.models, contains('ark-code-latest'));
    expect(coding.models, contains('deepseek-v4-pro'));
    expect(coding.models, contains('kimi-k3'));

    final ProviderProfile agent = kDefaultProviders
        .firstWhere((ProviderProfile p) => p.name == 'ark-agent-plan');
    expect(agent.baseUrl, 'https://ark.cn-beijing.volces.com/api/plan/v3');
    expect(agent.models, contains('deepseek-v4-1-flash'));
    expect(agent.models, contains('doubao-seed-2-0-lite-260215'));
    expect(agent.models, contains('minimax-m3'));
  });

  test('导入合并进注册表', () async {
    final ProviderRegistry registry = ProviderRegistry(
      store: store,
      builtin: <ProviderProfile>[profile('a')],
    );
    await registry.load();

    final ProviderImportResult result = await registry.importRegistry(
      url: 'https://registry.example/api.json',
      token: 'tok',
      client: _jsonClient(<String, Object?>{
        'providers': <Map<String, Object?>>[
          <String, Object?>{'name': 'imported', 'baseUrl': 'https://i/v1'},
        ],
      }),
    );

    expect(result.isSuccess, isTrue);
    expect(registry.byName('imported'), isNotNull);
  });
}
