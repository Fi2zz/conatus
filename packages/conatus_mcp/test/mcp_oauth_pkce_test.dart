/// PKCE（RFC 7636）生成测试：verifier 形态与 S256 challenge。
library;

import 'dart:convert';

import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

String _s256(String verifier) => base64Url
    .encode(sha256.convert(utf8.encode(verifier)).bytes)
    .replaceAll('=', '');

void main() {
  group('generatePkce', () {
    test('challenge 是 verifier 的 S256', () {
      final PkcePair pair = generatePkce();
      expect(pair.challenge, _s256(pair.verifier));
    });

    test('verifier 为 32 字节 base64url 无填充', () {
      final PkcePair pair = generatePkce();
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(pair.verifier), isTrue);
      expect(pair.verifier, isNot(contains('=')));
      expect(base64Url.decode('${pair.verifier}=').length, 32);
    });

    test('每次生成都不同', () {
      final Set<String> verifiers = <String>{
        for (int i = 0; i < 8; i++) generatePkce().verifier,
      };
      expect(verifiers, hasLength(8));
    });
  });
}
