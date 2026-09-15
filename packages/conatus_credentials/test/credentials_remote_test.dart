import 'dart:convert';

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// 记录最后一次请求并返回固定响应的测试替身。
class _Recorder {
  _Recorder(this.response);

  final http.Response response;
  http.Request? last;

  MockClient get client => MockClient((http.Request request) async {
        last = request;
        return response;
      });
}

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );

Matcher _hasCode(String code) => isA<CredentialsException>()
    .having((CredentialsException error) => error.code, 'code', code);

const VaultConfig _vaultConfig = VaultConfig(
  address: 'http://127.0.0.1:8200/',
  token: 'vault-token',
  path: 'conatus/llm',
);

const AwsSecretsConfig _awsConfig = AwsSecretsConfig(
  accessKey: 'AKIDEXAMPLE',
  secretKey: 'SECRET',
  region: 'us-east-1',
  secretId: 'conatus/llm',
);

void main() {
  group('VaultCredentials', () {
    test('URL / 方法与 Token 头正确，并解析 data.data', () async {
      final _Recorder recorder = _Recorder(_json(<String, Object>{
        'data': <String, Object>{
          'data': <String, Object>{
            'ARK_API_KEY': 'vault-key',
            'DEEPSEEK_API_KEY': <String, Object>{'value': 'ds-key'},
          },
        },
      }));
      final VaultCredentials credentials =
          VaultCredentials(config: _vaultConfig, client: recorder.client);
      await credentials.refresh();

      expect(recorder.last?.method, 'GET');
      expect(
        recorder.last?.url.toString(),
        'http://127.0.0.1:8200/v1/secret/data/conatus/llm',
      );
      expect(recorder.last?.headers['X-Vault-Token'], 'vault-token');
      expect(credentials.get('ARK_API_KEY')?.value, 'vault-key');
      expect(credentials.get('DEEPSEEK_API_KEY')?.value, 'ds-key');
      credentials.close();
    });

    test('自定义挂载点进入 URL 且地址尾斜杠被吃掉', () async {
      const Map<String, Object> empty = <String, Object>{
        'data': <String, Object>{'data': <String, Object>{}},
      };
      final _Recorder recorder = _Recorder(_json(empty));
      final VaultCredentials credentials = VaultCredentials(
        config: const VaultConfig(
          address: 'https://vault.example.com//',
          token: 't',
          path: 'llm',
          mount: 'kv',
        ),
        client: recorder.client,
      );
      await credentials.refresh();

      expect(
        recorder.last?.url.toString(),
        'https://vault.example.com/v1/kv/data/llm',
      );
      credentials.close();
    });

    test('非 200 抛 vault-http', () async {
      final _Recorder recorder =
          _Recorder(http.Response('permission denied', 403));
      final VaultCredentials credentials =
          VaultCredentials(config: _vaultConfig, client: recorder.client);
      await expectLater(credentials.refresh(), throwsA(_hasCode('vault-http')));
      expect(credentials.keys, isEmpty);
      credentials.close();
    });

    test('网络异常包成 vault-network', () async {
      final MockClient client = MockClient(
        (http.Request request) async =>
            throw http.ClientException('network down', request.url),
      );
      final VaultCredentials credentials =
          VaultCredentials(config: _vaultConfig, client: client);
      await expectLater(
        credentials.refresh(),
        throwsA(_hasCode('vault-network')),
      );
      credentials.close();
    });
  });

  group('AwsSecretsCredentials', () {
    test('带签名头，并把 JSON 形态的 SecretString 展开成多键', () async {
      final _Recorder recorder = _Recorder(_json(<String, String>{
        'SecretString': jsonEncode(<String, String>{
          'ARK_API_KEY': 'aws-key',
          'DEEPSEEK_API_KEY': 'ds-key',
        }),
      }));
      final AwsSecretsCredentials credentials =
          AwsSecretsCredentials(config: _awsConfig, client: recorder.client);
      await credentials.refresh();

      final http.Request request = recorder.last!;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://secretsmanager.us-east-1.amazonaws.com/',
      );
      expect(request.headers['X-Amz-Target'], 'secretsmanager.GetSecretValue');
      expect(
        request.headers['Authorization'],
        startsWith('AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/'),
      );
      expect(request.headers['Authorization'], contains('SignedHeaders='));
      expect(
        RegExp(r'^\d{8}T\d{6}Z$').hasMatch(request.headers['X-Amz-Date'] ?? ''),
        isTrue,
      );
      expect(
        jsonDecode(request.body),
        <String, Object>{'SecretId': 'conatus/llm'},
      );
      expect(credentials.get('ARK_API_KEY')?.value, 'aws-key');
      expect(credentials.get('DEEPSEEK_API_KEY')?.value, 'ds-key');
      credentials.close();
    });

    test('SecretString 非 JSON 时以 secretId 为单一键', () async {
      final _Recorder recorder =
          _Recorder(_json(<String, String>{'SecretString': 'plain-secret'}));
      final AwsSecretsCredentials credentials =
          AwsSecretsCredentials(config: _awsConfig, client: recorder.client);
      await credentials.refresh();

      expect(credentials.keys, <String>['conatus/llm']);
      expect(credentials.get('conatus/llm')?.value, 'plain-secret');
      credentials.close();
    });

    test('自定义端点与 sessionToken', () async {
      final _Recorder recorder =
          _Recorder(_json(<String, String>{'SecretString': 'plain-secret'}));
      final AwsSecretsCredentials credentials = AwsSecretsCredentials(
        config: const AwsSecretsConfig(
          accessKey: 'AKIDEXAMPLE',
          secretKey: 'SECRET',
          region: 'us-east-1',
          secretId: 'llm',
          sessionToken: 'SESSION-TOKEN',
          endpoint: 'http://127.0.0.1:4566/',
        ),
        client: recorder.client,
      );
      await credentials.refresh();

      expect(recorder.last?.url.toString(), 'http://127.0.0.1:4566/');
      expect(recorder.last?.headers['X-Amz-Security-Token'], 'SESSION-TOKEN');
      credentials.close();
    });

    test('非 200 抛 aws-http', () async {
      final _Recorder recorder = _Recorder(http.Response('denied', 400));
      final AwsSecretsCredentials credentials =
          AwsSecretsCredentials(config: _awsConfig, client: recorder.client);
      await expectLater(credentials.refresh(), throwsA(_hasCode('aws-http')));
      credentials.close();
    });
  });
}
