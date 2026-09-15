import 'dart:convert';

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

const String _payload = '{"SecretId": "conatus/llm"}';

final Uri _uri = Uri.parse('https://secretsmanager.us-east-1.amazonaws.com/');

const Map<String, String> _businessHeaders = <String, String>{
  'Content-Type': 'application/x-amz-json-1.1',
  'X-Amz-Target': 'secretsmanager.GetSecretValue',
};

/// 用固定时间戳签名，保证断言稳定。
Map<String, String> _sign({String? sessionToken, DateTime? timestamp}) {
  final SigV4Signer signer = SigV4Signer(
    accessKey: 'AKIDEXAMPLE',
    secretKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
    region: 'us-east-1',
    service: 'secretsmanager',
    sessionToken: sessionToken,
  );
  return signer.sign(
    method: 'POST',
    uri: _uri,
    headers: _businessHeaders,
    payload: _payload,
    timestamp: timestamp ?? DateTime.utc(2024),
  );
}

void main() {
  group('SigV4Signer', () {
    test('同输入同输出', () {
      expect(_sign(), _sign());
      final DateTime other = DateTime.utc(2024, 3, 4);
      expect(_sign(timestamp: other), _sign(timestamp: other));
    });

    test('X-Amz-Content-Sha256 等于 payload 的 sha256 十六进制', () {
      expect(
        _sign()['X-Amz-Content-Sha256'],
        sha256.convert(utf8.encode(_payload)).toString(),
      );
    });

    test('X-Amz-Date 为 UTC 紧凑格式', () {
      expect(_sign()['X-Amz-Date'], '20240101T000000Z');
      expect(
        _sign(timestamp: DateTime.parse('2024-05-06T07:08:09+02:00'))[
            'X-Amz-Date'],
        '20240506T050809Z',
      );
    });

    test('业务头保留原大小写，SignedHeaders 用小写排序', () {
      final Map<String, String> headers = _sign();
      expect(headers['X-Amz-Target'], 'secretsmanager.GetSecretValue');
      expect(headers['Content-Type'], 'application/x-amz-json-1.1');
      expect(
        headers['Authorization'],
        contains('SignedHeaders=content-type;host;x-amz-content-sha256;'
            'x-amz-date;x-amz-target'),
      );
    });

    test('sessionToken 进入签名头', () {
      final Map<String, String> headers = _sign(sessionToken: 'SESSION-TOKEN');
      expect(headers['X-Amz-Security-Token'], 'SESSION-TOKEN');
      expect(headers['Authorization'], contains('x-amz-security-token'));
      expect(_sign()['X-Amz-Security-Token'], isNull);
    });

    test('对已知向量给出相同签名', () {
      // 向量由 AWS 文档四步流程的独立实现（Python hmac/hashlib）交叉核验。
      expect(
        _sign()['Authorization'],
        'AWS4-HMAC-SHA256 '
        'Credential=AKIDEXAMPLE/20240101/us-east-1/secretsmanager/aws4_request, '
        'SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date;'
        'x-amz-target, '
        'Signature=d38ab2c13c5fb2ba790a04f28dfd22c1b38df0536c544eec9b554d2f4bd24c8c',
      );
    });
  });
}
