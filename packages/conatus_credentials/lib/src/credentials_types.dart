/// 凭据词汇：凭据值对象、来源枚举与稳定错误码异常。
library;

import 'package:conatus_core/conatus_core.dart';

/// 一条凭据：键、明文值，以及可选的过期时刻。
class Credential {
  const Credential({required this.key, required this.value, this.expiresAt});

  /// 凭据键名（如 `ARK_API_KEY`）。
  final String key;

  /// 凭据明文值。**不要**把它写进日志或事件，用 [masked]。
  final String value;

  /// 过期时刻；`null` 表示永不过期。
  final DateTime? expiresAt;

  /// 脱敏表示（前 4 位 + `...` + 后 4 位），用于日志、事件与遥测。
  String get masked => maskSecret(value);

  /// 是否已过期：仅当 [expiresAt] 非空且早于当前时刻。
  bool get expired {
    final DateTime? deadline = expiresAt;
    return deadline != null && deadline.isBefore(DateTime.now());
  }

  @override
  String toString() => 'Credential($key, $masked)';
}

/// 带稳定错误码的凭据异常。
class CredentialsException implements Exception {
  const CredentialsException(this.code, this.message);

  /// 机器可路由的错误码（`missing` / `read-only` / `vault-http` / `aws-http`）。
  final String code;

  /// 人可读的消息。
  final String message;

  @override
  String toString() => 'CredentialsException($code): $message';
}

/// 凭据来源类型。
enum CredentialsSource { env, file, memory, vault, aws }

/// 把 JSON 对象解析成凭据表。每项支持两种形态：
///
/// * 字符串 —— 直接作为值；
/// * 对象 —— 读 `value`（字符串）与可选的 `expiresAt`（ISO 8601）。
///
/// [raw] 不是对象时返回空表；单项形态不合法（数字、布尔、缺 `value` 的对象等）
/// 时跳过该项。env / file / vault / aws 四种来源共用这一解析口径。
Map<String, Credential> parseCredentialMap(Object? raw) {
  final Map<String, Credential> result = <String, Credential>{};
  if (raw is! Map) return result;
  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    final Object? key = entry.key;
    if (key is! String) continue;
    final Credential? credential = _parseCredential(key, entry.value);
    if (credential != null) result[key] = credential;
  }
  return result;
}

Credential? _parseCredential(String key, Object? raw) {
  if (raw is String) return Credential(key: key, value: raw);
  if (raw is! Map) return null;
  final Object? value = raw['value'];
  if (value is! String) return null;
  return Credential(key: key, value: value, expiresAt: _parseTime(raw));
}

DateTime? _parseTime(Map<dynamic, dynamic> raw) {
  final Object? expiresAt = raw['expiresAt'];
  return expiresAt is String ? DateTime.tryParse(expiresAt) : null;
}
