import 'dart:async';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:test/test.dart';

/// 可观测 `close` 的测试替身；只提供读能力，用于装配测试。
class _RecordingCredentials extends Credentials {
  _RecordingCredentials({Map<String, String> values = const <String, String>{}})
      : _values = values;

  final Map<String, String> _values;
  final StreamController<Credential> _changes =
      StreamController<Credential>.broadcast();

  bool closed = false;

  @override
  List<String> get keys => _values.keys.toList();

  @override
  Stream<Credential> get changes => _changes.stream;

  @override
  Credential? get(String key) {
    final String? value = _values[key];
    return value == null ? null : Credential(key: key, value: value);
  }

  @override
  Future<void> update(String key, String value) async {
    _values[key] = value;
  }

  @override
  void close() {
    closed = true;
    unawaited(_changes.close());
  }
}

Matcher _hasCode(String code) => isA<CredentialsException>()
    .having((CredentialsException error) => error.code, 'code', code);

void main() {
  group('Credential', () {
    test('masked 保留前 4 后 4', () {
      const Credential credential =
          Credential(key: 'K', value: '1234567890abcd');
      expect(credential.masked, '1234...abcd');
      expect(credential.toString(), 'Credential(K, 1234...abcd)');
    });

    test('短值整体星号遮蔽', () {
      expect(const Credential(key: 'K', value: 'abc').masked, '***');
      expect(const Credential(key: 'K', value: '').masked, '');
      expect(const Credential(key: 'K', value: '12345678').masked, '********');
    });

    test('expired 以 expiresAt 判定', () {
      final Credential past = Credential(
        key: 'K',
        value: 'v',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final Credential future = Credential(
        key: 'K',
        value: 'v',
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      );
      expect(past.expired, true);
      expect(future.expired, false);
      expect(const Credential(key: 'K', value: 'v').expired, false);
    });

    test('异常 toString 带错误码', () {
      const CredentialsException error = CredentialsException('missing', '缺 A');
      expect(error.code, 'missing');
      expect(error.toString(), 'CredentialsException(missing): 缺 A');
    });
  });

  group('Credentials 契约', () {
    test('validate 快速失败并列出全部缺失键', () {
      final InMemoryCredentials credentials =
          InMemoryCredentials(initial: <String, String>{'B': 'b'});
      expect(
        () => credentials.validate(<String>['A', 'B', 'C']),
        throwsA(
          isA<CredentialsException>()
              .having((CredentialsException e) => e.code, 'code', 'missing')
              .having((CredentialsException e) => e.message, 'message',
                  allOf(contains('A'), contains('C'))),
        ),
      );
    });

    test('validate 键齐备时不抛', () {
      final InMemoryCredentials credentials =
          InMemoryCredentials(initial: <String, String>{'A': 'a', 'B': 'b'});
      expect(() => credentials.validate(<String>['A', 'B']), returnsNormally);
    });

    test('require 缺失时抛 missing', () {
      final InMemoryCredentials credentials = InMemoryCredentials();
      expect(credentials.get('NOPE'), isNull);
      expect(() => credentials.require('NOPE'), throwsA(_hasCode('missing')));
    });

    test('provider 装配后可见，重复提供抛 StateError', () {
      final Context ctx = Context.root();
      final Credentials credentials = provideCredentials(ctx);
      expect(credentials, isA<EnvCredentials>());
      expect(ctx.credentials, same(credentials));
      expect(() => provideCredentials(ctx), throwsA(isA<StateError>()));
      ctx.dispose();
    });

    test('ctx.dispose() 触发 close()', () {
      final Context ctx = Context.root();
      final _RecordingCredentials fake =
          _RecordingCredentials(values: <String, String>{'ARK_API_KEY': 'key'});
      provideCredentials(ctx, credentials: fake);
      expect(ctx.credentials.get('ARK_API_KEY')?.value, 'key');
      ctx.dispose();
      expect(fake.closed, true);
    });
  });

  group('InMemoryCredentials', () {
    test('update 生效并推送 changes', () async {
      final InMemoryCredentials credentials =
          InMemoryCredentials(initial: <String, String>{'ARK_API_KEY': 'old'});
      expect(credentials.get('ARK_API_KEY')?.value, 'old');

      final Future<Credential> pushed = credentials.changes.first;
      await credentials.update('ARK_API_KEY', 'new');

      expect((await pushed).value, 'new');
      expect(credentials.get('ARK_API_KEY')?.value, 'new');
      expect(credentials.keys, <String>['ARK_API_KEY']);
    });

    test('refresh 不改变快照', () async {
      final InMemoryCredentials credentials =
          InMemoryCredentials(initial: <String, String>{'A': 'a'});
      await credentials.refresh();
      expect(credentials.get('A')?.value, 'a');
    });

    test('close 后不再推送', () async {
      final InMemoryCredentials credentials = InMemoryCredentials();
      credentials.close();
      await credentials.update('A', 'a');
      expect(credentials.get('A'), isNull);
    });
  });
}
