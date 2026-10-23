/// OAuth 令牌存储：0600、原子写、round-trip、损坏文件降级。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late McpOAuthStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mcp-oauth-store-');
    addTearDown(() => dir.deleteSync(recursive: true));
    store = McpOAuthStore(dir.path);
  });

  File fileOf(String server) => File('${dir.path}/$server.json');

  test('写入 0600 并完整 round-trip', () async {
    final DateTime expires = DateTime.utc(2027, 1, 2, 3, 4, 5);
    await store.save(
      'docs',
      McpOAuthToken(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: expires,
        scope: 'mcp',
      ).withClient(clientId: 'cid', clientSecret: 'csecret'),
    );

    final McpOAuthToken token = (await store.load('docs'))!;

    expect(token.accessToken, 'a');
    expect(token.refreshToken, 'r');
    expect(token.expiresAt, expires);
    expect(token.scope, 'mcp');
    expect(token.clientId, 'cid');
    expect(token.clientSecret, 'csecret');
    expect(fileOf('docs').statSync().mode & 0x1FF, 0x180);
    expect(dir.statSync().mode & 0x1FF, 0x1C0);
  });

  test('a/b 与 a_b 使用不同令牌文件，互不覆盖', () async {
    await store.save('a/b', const McpOAuthToken(accessToken: 'slash'));
    await store.save('a_b', const McpOAuthToken(accessToken: 'underscore'));

    expect((await store.load('a/b'))!.accessToken, 'slash');
    expect((await store.load('a_b'))!.accessToken, 'underscore');
    expect(dir.listSync(), hasLength(2));
  });

  test('重复保存覆盖旧文件，且不留临时文件', () async {
    await store.save('docs', const McpOAuthToken(accessToken: 'old'));
    await store.save('docs', const McpOAuthToken(accessToken: 'new'));

    expect((await store.load('docs'))!.accessToken, 'new');
    expect(
      dir.listSync().map((FileSystemEntity entity) => entity.path).toList(),
      <String>[fileOf('docs').path],
    );
  });

  test('remove 删除文件；重复 remove 不抛', () async {
    await store.save('docs', const McpOAuthToken(accessToken: 'a'));
    await store.remove('docs');
    await store.remove('docs');

    expect(await store.load('docs'), isNull);
    expect(fileOf('docs').existsSync(), isFalse);
  });

  test('未保存过的 server 返回 null', () async {
    expect(await store.load('missing'), isNull);
  });

  test('损坏 / 非对象 JSON 降级为 null', () async {
    Directory(dir.path).createSync(recursive: true);
    fileOf('bad').writeAsStringSync('{不是 JSON');
    fileOf('list').writeAsStringSync('[1,2]');

    expect(await store.load('bad'), isNull);
    expect(await store.load('list'), isNull);
  });

  test('server 名安全化：路径分隔符不能逃出令牌目录', () async {
    await store.save('../../evil', const McpOAuthToken(accessToken: 'a'));

    expect((await store.load('../../evil'))!.accessToken, 'a');
    expect(
      dir.listSync(),
      everyElement(isA<File>()),
    );
    expect(File('${dir.path}/../../evil.json').existsSync(), isFalse);
  });

  test('令牌字段不出现在 toString 里', () {
    const McpOAuthToken token = McpOAuthToken(
      accessToken: 'access-secret',
      refreshToken: 'refresh-secret',
    );

    expect(token.toString(), isNot(contains('access-secret')));
    expect(token.toString(), isNot(contains('refresh-secret')));
  });

  test('needsRefresh：过期前 60 秒内为真，缺 expiresAt 为假', () {
    final DateTime now = DateTime.now();
    expect(const McpOAuthToken(accessToken: 'a').needsRefresh, isFalse);
    expect(
      McpOAuthToken(
        accessToken: 'a',
        expiresAt: now.add(const Duration(seconds: 30)),
      ).needsRefresh,
      isTrue,
    );
    expect(
      McpOAuthToken(
        accessToken: 'a',
        expiresAt: now.add(const Duration(minutes: 5)),
      ).needsRefresh,
      isFalse,
    );
  });

  test('落盘 JSON 只含协议字段，不夹带额外内容', () async {
    await store.save('docs', const McpOAuthToken(accessToken: 'a'));
    final Map<String, Object?> raw =
        jsonDecode(await fileOf('docs').readAsString()) as Map<String, Object?>;

    expect(raw.keys, <String>['access_token']);
  });
}
