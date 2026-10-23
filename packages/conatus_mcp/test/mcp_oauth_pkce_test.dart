/// PKCE（RFC 7636）生成测试：verifier 形态与 S256 challenge。
library;

import 'dart:convert';
import 'dart:math';

import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

String _s256(String verifier) => base64Url
    .encode(sha256.convert(utf8.encode(verifier)).bytes)
    .replaceAll('=', '');

void main() {
  group('generatePkce', () {
    test('RFC 7636 Appendix B 向量', () {
      final PkcePair pair = generatePkce(
        random: _FixedRandom(
          base64Url.decode('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk='),
        ),
      );
      expect(pair.verifier, 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk');
      expect(pair.challenge, 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });

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

/// 按预置字节序列返回随机数（复现 RFC 7636 附录 B 向量）。
class _FixedRandom implements Random {
  _FixedRandom(this.bytes);

  final List<int> bytes;
  int _offset = 0;

  @override
  int nextInt(int max) => bytes[_offset++];

  @override
  bool nextBool() => throw UnsupportedError('固定随机源不支持 nextBool');

  @override
  double nextDouble() => throw UnsupportedError('固定随机源不支持 nextDouble');
}
