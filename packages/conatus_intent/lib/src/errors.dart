/// 意图路由的错误词汇。
library;

/// Intent 相关错误。
///
/// [code] 是稳定的机器可读错误码（`duplicate` / `not-serializable` /
/// `invalid-config` / `missing-field` / `bad-type` / `unknown-action` /
/// `unknown-handler`），[message] 面向排障。
class IntentException implements Exception {
  /// 构造异常。
  const IntentException(this.code, this.message);

  /// 稳定的机器可读错误码。
  final String code;

  /// 可读消息。
  final String message;

  @override
  String toString() => 'IntentException($code): $message';
}
