/// PKCE（RFC 7636）参数生成：S256 challenge。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 一对 PKCE 参数：明文 [verifier] 本地保留，[challenge] 随授权请求下发。
class PkcePair {
  /// 直接构造。
  const PkcePair({required this.verifier, required this.challenge});

  /// 高熵随机串（32 字节 base64url，无填充）。
  final String verifier;

  /// `base64url(sha256(verifier))`，无填充。
  final String challenge;
}

/// 生成一对 PKCE 参数（[Random.secure]，每次不同）。
PkcePair generatePkce({Random? random}) {
  final Random source = random ?? Random.secure();
  final List<int> bytes = List<int>.generate(32, (_) => source.nextInt(256));
  final String verifier = _base64Url(bytes);
  final String challenge =
      _base64Url(sha256.convert(utf8.encode(verifier)).bytes);
  return PkcePair(verifier: verifier, challenge: challenge);
}

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');
