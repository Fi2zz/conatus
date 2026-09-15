import 'dart:convert';
import 'dart:io';

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:test/test.dart';

Matcher _hasCode(String code) => isA<CredentialsException>()
    .having((CredentialsException error) => error.code, 'code', code);

void main() {
  group('EnvCredentials', () {
    test('构造时装入非空环境变量', () {
      final EnvCredentials credentials = EnvCredentials(
        environment: <String, String>{'ARK_API_KEY': 'env-key', 'EMPTY': ''},
      );
      expect(credentials.get('ARK_API_KEY')?.value, 'env-key');
      expect(credentials.get('EMPTY'), isNull);
      expect(credentials.keys, <String>['ARK_API_KEY']);
    });

    test('update 抛 read-only', () async {
      final EnvCredentials credentials =
          EnvCredentials(environment: const <String, String>{});
      await expectLater(
        credentials.update('A', 'B'),
        throwsA(_hasCode('read-only')),
      );
    });

    test('refresh 重读环境', () async {
      final Map<String, String> environment = <String, String>{'A': '1'};
      final EnvCredentials credentials =
          EnvCredentials(environment: environment);
      environment['B'] = '2';
      await credentials.refresh();
      expect(credentials.get('B')?.value, '2');
    });

    test('缺省读 Platform.environment', () {
      final EnvCredentials credentials = EnvCredentials();
      expect(credentials.keys, containsAll(Platform.environment.keys));
    });
  });

  group('FileCredentials', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('conatus_credentials');
      file = File('${dir.path}/credentials.json');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('读字符串与对象两种形态', () async {
      file.writeAsStringSync(jsonEncode(<String, Object>{
        'ARK_API_KEY': 'file-key',
        'DEEPSEEK_API_KEY': <String, Object>{
          'value': 'ds-key',
          'expiresAt': '2999-01-01T00:00:00Z',
        },
        'COUNT': 3,
      }));
      final FileCredentials credentials = FileCredentials(path: file.path);
      await credentials.load();

      expect(credentials.get('ARK_API_KEY')?.value, 'file-key');
      expect(credentials.get('DEEPSEEK_API_KEY')?.value, 'ds-key');
      expect(credentials.get('COUNT'), isNull);
      credentials.close();
    });

    test('refresh 读到新内容并推送变化', () async {
      file.writeAsStringSync(jsonEncode(<String, String>{'A': 'old'}));
      final FileCredentials credentials = FileCredentials(path: file.path);
      await credentials.load();
      expect(credentials.get('A')?.value, 'old');

      final Future<Credential> pushed = credentials.changes.first;
      file.writeAsStringSync(jsonEncode(<String, String>{'A': 'new'}));
      await credentials.refresh();

      expect(credentials.get('A')?.value, 'new');
      expect((await pushed).value, 'new');
      credentials.close();
    });

    test('文件缺失时用 fallback', () async {
      final FileCredentials credentials = FileCredentials(
        path: '${dir.path}/missing.json',
        fallback: <String, String>{'A': 'fallback'},
      );
      await credentials.load();
      expect(credentials.get('A')?.value, 'fallback');
      expect(credentials.keys, <String>['A']);
      credentials.close();
    });

    test('文件缺失且无 fallback 时快照为空', () async {
      final FileCredentials credentials =
          FileCredentials(path: '${dir.path}/missing.json');
      await credentials.load();
      expect(credentials.keys, isEmpty);
      expect(credentials.get('A'), isNull);
      credentials.close();
    });

    test('过期凭据视为缺失', () async {
      file.writeAsStringSync(jsonEncode(<String, Object>{
        'A': <String, Object>{
          'value': 'stale',
          'expiresAt': '2020-01-01T00:00:00Z',
        },
      }));
      final FileCredentials credentials = FileCredentials(path: file.path);
      await credentials.load();

      expect(credentials.get('A'), isNull);
      expect(() => credentials.require('A'), throwsA(_hasCode('missing')));
      credentials.close();
    });

    test('update 抛 read-only 且 close 幂等', () async {
      final FileCredentials credentials =
          FileCredentials(path: '${dir.path}/missing.json');
      await expectLater(
        credentials.update('A', 'B'),
        throwsA(_hasCode('read-only')),
      );
      credentials.close();
      credentials.close();
    });

    test('refreshInterval 定时重读', () async {
      file.writeAsStringSync(jsonEncode(<String, String>{'A': 'first'}));
      final FileCredentials credentials = FileCredentials(
        path: file.path,
        refreshInterval: const Duration(milliseconds: 20),
      );
      await credentials.load();
      final Future<Credential> pushed = credentials.changes.first;
      file.writeAsStringSync(jsonEncode(<String, String>{'A': 'second'}));

      expect((await pushed).value, 'second');
      credentials.close();
    });
  });
}
