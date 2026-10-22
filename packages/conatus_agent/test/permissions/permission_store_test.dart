/// 项目级权限规则存储：JSON 往返、原子发布、0600 与坏文件兜底。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:test/test.dart';

/// 取文件权限位（低 12 位）。
int _permissionBits(String path) => File(path).statSync().mode & 0xFFF;

const PermissionRule _shellDeny = PermissionRule(
  action: 'shell',
  resource: 'git push *',
  effect: PermissionEffect.deny,
  source: 'project',
);

const PermissionRule _editAsk = PermissionRule(
  action: 'edit',
  resource: '*.env',
  effect: PermissionEffect.ask,
);

void main() {
  late Directory dir;
  late String path;
  late PermissionStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-permission-store-');
    path = '${dir.path}/permissions.json';
    store = PermissionStore(path);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('文件不存在时载入空列表', () async {
    expect(await store.load(), isEmpty);
  });

  test('save → load 往返保留全部字段', () async {
    await store.save(<PermissionRule>[_shellDeny, _editAsk]);

    final List<PermissionRule> loaded = await store.load();
    expect(loaded, hasLength(2));
    expect(loaded[0].action, 'shell');
    expect(loaded[0].resource, 'git push *');
    expect(loaded[0].effect, PermissionEffect.deny);
    expect(loaded[0].source, 'project');
    expect(loaded[1].effect, PermissionEffect.ask);
    expect(loaded[1].source, isNull);
  });

  test('落盘结构为 version 1 + rules 数组', () async {
    await store.save(<PermissionRule>[_shellDeny]);

    final Object? json = jsonDecode(await File(path).readAsString());
    expect(json, isA<Map<String, Object?>>());
    final Map<String, Object?> root = json! as Map<String, Object?>;
    expect(root['version'], 1);
    final List<Object?> rules = root['rules']! as List<Object?>;
    expect(rules, hasLength(1));
    expect(
      rules.single,
      <String, Object?>{
        'action': 'shell',
        'resource': 'git push *',
        'effect': 'deny',
        'source': 'project',
      },
    );
  });

  test('父目录不存在时自动创建', () async {
    final String nested = '${dir.path}/a/b/permissions.json';
    await PermissionStore(nested).save(<PermissionRule>[_editAsk]);

    expect(File(nested).existsSync(), isTrue);
    expect(await PermissionStore(nested).load(), hasLength(1));
  });

  test('保存后目录里没有临时文件残留', () async {
    await store.save(<PermissionRule>[_shellDeny]);
    await store.save(<PermissionRule>[_editAsk]);

    final List<String> names = dir
        .listSync()
        .map((FileSystemEntity entity) => entity.path.split('/').last)
        .toList();
    expect(names, <String>['permissions.json']);
  });

  test('文件权限收紧为 0600', () async {
    await store.save(<PermissionRule>[_shellDeny]);

    expect(_permissionBits(path), 0x180); // 0o600
  }, testOn: '!windows');

  test('损坏 JSON 返回空列表而不抛错', () async {
    await File(path).writeAsString('{not json');

    expect(await store.load(), isEmpty);
  });

  test('未知版本返回空列表', () async {
    await File(path).writeAsString('{"version":2,"rules":[]}');

    expect(await store.load(), isEmpty);
  });

  test('顶层不是对象时返回空列表', () async {
    await File(path).writeAsString('[1,2,3]');

    expect(await store.load(), isEmpty);
  });

  test('非法规则条目被跳过，合法条目照常载入', () async {
    await File(path).writeAsString(jsonEncode(<String, Object?>{
      'version': 1,
      'rules': <Object?>[
        <String, Object?>{
          'action': 'shell',
          'resource': '*',
          'effect': 'bogus'
        },
        <String, Object?>{'action': 'shell', 'effect': 'deny'},
        <String, Object?>{'action': '', 'resource': '*', 'effect': 'deny'},
        'not-an-object',
        <String, Object?>{
          'action': 'edit',
          'resource': '*.env',
          'effect': 'ask',
          'source': 'session',
        },
      ],
    }));

    final List<PermissionRule> loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.action, 'edit');
    expect(loaded.single.effect, PermissionEffect.ask);
    expect(loaded.single.source, 'session');
  });

  test('add 追加到已有规则之后', () async {
    await store.save(<PermissionRule>[_shellDeny]);
    await store.add(_editAsk);

    final List<PermissionRule> loaded = await store.load();
    expect(loaded.map((PermissionRule rule) => rule.action),
        <String>['shell', 'edit']);
    expect(loaded.last.effect, PermissionEffect.ask);
  });

  test('文件不存在时 add 也能建立文件', () async {
    await store.add(_editAsk);

    expect(File(path).existsSync(), isTrue);
    expect(await store.load(), hasLength(1));
  });

  test('空列表保存后载回空列表', () async {
    await store.save(<PermissionRule>[_shellDeny]);
    await store.save(const <PermissionRule>[]);

    expect(await store.load(), isEmpty);
  });
}
