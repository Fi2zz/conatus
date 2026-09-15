/// AWS Signature Version 4（SigV4）签名，供 Secrets Manager 等 AWS 来源复用。
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';

/// SigV4 签名器：把请求要素签成 AWS 要求的鉴权头。
///
/// 只覆盖 `Authorization` 头签法（非 presigned URL），算法固定
/// `AWS4-HMAC-SHA256`。参与签名的头：`host`（取自 [Uri.host]）、
/// `x-amz-date`、`x-amz-content-sha256`、可选的 `x-amz-security-token`，
/// 以及调用方传入的其余头（如 `X-Amz-Target`）。时间戳由调用方显式传入，
/// 因此同一输入必然得到同一输出，便于单测与复现。
class SigV4Signer {
  SigV4Signer({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    required this.service,
    this.sessionToken,
  });

  /// 访问密钥 ID（`AKIA...` / `ASIA...`）。
  final String accessKey;

  /// 访问密钥密文。
  final String secretKey;

  /// 区域（如 `us-east-1`），进入签名 scope。
  final String region;

  /// 服务名（如 `secretsmanager`），进入签名 scope。
  final String service;

  /// 临时凭证的会话令牌；非空时随 `X-Amz-Security-Token` 发送并参与签名。
  final String? sessionToken;

  /// 对一次请求签名，返回**可原样发送**的完整头表。
  ///
  /// [headers] 是调用方打算发送的业务头，不含本方法自行生成的
  /// `Authorization` / `X-Amz-Date` / `X-Amz-Content-Sha256` /
  /// `X-Amz-Security-Token`。`Host` 由 HTTP 客户端按 [uri] 自动发送，
  /// 故不写回结果，但一定进入 SignedHeaders。
  Map<String, String> sign({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String payload,
    required DateTime timestamp,
  }) {
    final String amzDate = _amzDate(timestamp);
    final Map<String, String> signed =
        _signedHeaders(uri, headers, amzDate, payload);
    final String scope =
        '${amzDate.substring(0, 8)}/$region/$service/aws4_request';
    final String signature = _signature(
      scope: scope,
      amzDate: amzDate,
      canonicalRequest: _canonicalRequest(method, uri, signed),
    );
    return <String, String>{
      ...headers,
      'X-Amz-Date': amzDate,
      'X-Amz-Content-Sha256': signed['x-amz-content-sha256']!,
      if (sessionToken != null) 'X-Amz-Security-Token': sessionToken!,
      'Authorization': 'AWS4-HMAC-SHA256 Credential=$accessKey/$scope, '
          'SignedHeaders=${_signedNames(signed).join(';')}, '
          'Signature=$signature',
    };
  }

  /// 进入规范请求的头：业务头小写化，再补 host 与 `x-amz-*` 系统头。
  Map<String, String> _signedHeaders(
    Uri uri,
    Map<String, String> headers,
    String amzDate,
    String payload,
  ) =>
      <String, String>{
        for (final MapEntry<String, String> entry in headers.entries)
          entry.key.toLowerCase(): entry.value,
        'host': uri.host,
        'x-amz-date': amzDate,
        'x-amz-content-sha256': _sha256(payload),
        if (sessionToken != null) 'x-amz-security-token': sessionToken!,
      };

  String _signature({
    required String scope,
    required String amzDate,
    required String canonicalRequest,
  }) =>
      _hmac(
        _signingKey(
          secretKey: secretKey,
          dateStamp: amzDate.substring(0, 8),
          region: region,
          service: service,
        ),
        <String>[
          'AWS4-HMAC-SHA256',
          amzDate,
          scope,
          _sha256(canonicalRequest),
        ].join('\n'),
      );
}

/// 规范请求：method / 规范 URI / 规范查询串 / 规范头 / SignedHeaders /
/// 载荷哈希，六段以 `\n` 相连。
String _canonicalRequest(String method, Uri uri, Map<String, String> signed) {
  final List<String> names = _signedNames(signed);
  final String headers =
      '${names.map((String name) => '$name:${signed[name]!.trim()}').join('\n')}\n';
  return <String>[
    method,
    _canonicalUri(uri),
    _canonicalQuery(uri),
    headers,
    names.join(';'),
    signed['x-amz-content-sha256']!,
  ].join('\n');
}

List<String> _signedNames(Map<String, String> signed) =>
    signed.keys.toList()..sort();

List<int> _signingKey({
  required String secretKey,
  required String dateStamp,
  required String region,
  required String service,
}) {
  final List<int> dateKey =
      _hmacBytes(utf8.encode('AWS4$secretKey'), dateStamp);
  final List<int> regionKey = _hmacBytes(dateKey, region);
  final List<int> serviceKey = _hmacBytes(regionKey, service);
  return _hmacBytes(serviceKey, 'aws4_request');
}

List<int> _hmacBytes(List<int> key, String data) =>
    Hmac(sha256, key).convert(utf8.encode(data)).bytes;

String _hmac(List<int> key, String data) =>
    Hmac(sha256, key).convert(utf8.encode(data)).toString();

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

/// 规范 URI：`Uri.path` 已是百分号编码形态，故按解码后的段重新编码，
/// 避免对已编码的段二次编码（`%20` → `%2520`）。
String _canonicalUri(Uri uri) {
  if (uri.pathSegments.isEmpty) return '/';
  return '/${uri.pathSegments.map(Uri.encodeComponent).join('/')}';
}

String _canonicalQuery(Uri uri) {
  final List<String> pairs = <String>[
    for (final MapEntry<String, List<String>> entry
        in uri.queryParametersAll.entries)
      for (final String value in entry.value)
        '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(value)}',
  ]..sort();
  return pairs.join('&');
}

String _amzDate(DateTime timestamp) {
  final DateTime utc = timestamp.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}'
      '${two(utc.month)}${two(utc.day)}'
      'T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}
