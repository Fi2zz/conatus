/// 敏感信息脱敏：日志、事件与遥测中凭据绝不以明文出现。
///
/// 键名匹配 `*_KEY` / `*_TOKEN` / `*_SECRET` / `*_PASSWORD` 等形式时，其字符串
/// 值会被替换为 [maskSecret] 的脱敏表示；对象与列表递归处理。规则大小写不敏感，
/// 且同时兼容下划线、连字符与驼峰（如 `apiKey`、`api-key`、`api_key`）。
library;

/// 敏感键名的规范化词元：键名按非字母数字拆分并转小写后，命中其一即视为敏感。
const Set<String> _sensitiveTokens = <String>{
  'key',
  'apikey',
  'token',
  'secret',
  'password',
  'passwd',
  'authorization',
  'credential',
  'credentials',
  'privatekey',
  'accesskey',
  'secretkey',
};

/// 键名是否类似凭据字段。
bool isSensitiveKey(String key) {
  final String normalized =
      key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (normalized.isEmpty) return false;
  if (_lookupToken(normalized)) return true;
  // 下划线/连字符风格：任意一段命中即敏感（`ARK_API_KEY` → `api` + `key`）。
  final Iterable<String> parts =
      key.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((p) => p.isNotEmpty);
  for (final String part in parts) {
    if (_lookupToken(part)) return true;
  }
  return false;
}

bool _lookupToken(String token) {
  if (_sensitiveTokens.contains(token)) return true;
  // 简单复数：`keys` / `tokens` / `secrets`。
  return token.endsWith('s') && _sensitiveTokens.contains(token.substring(0, token.length - 1));
}

/// 凭据的脱敏表示：前 4 位 + `...` + 后 4 位。
///
/// 长度不足 8 时不做局部保留，直接以等长星号遮蔽，避免短密钥被几乎完整暴露。
String maskSecret(String value) {
  if (value.isEmpty) return '';
  if (value.length <= 8) return '*' * value.length;
  return '${value.substring(0, 4)}...${value.substring(value.length - 4)}';
}

/// 递归脱敏：键名命中 [isSensitiveKey] 的字符串值会被 [maskSecret] 遮蔽。
///
/// 非字符串的敏感值（如数字）同样被遮蔽为 `***`，避免结构化凭据外泄。
/// 不修改入参，返回新的 [Map] / [List]；其余标量原样返回。
Object? redactSecrets(Object? value) {
  if (value is Map) {
    final Map<Object?, Object?> result = <Object?, Object?>{};
    value.forEach((Object? key, Object? item) {
      if (key is String && isSensitiveKey(key)) {
        result[key] = _maskValue(item);
      } else {
        result[key] = redactSecrets(item);
      }
    });
    return result;
  }
  if (value is List) {
    return <Object?>[for (final Object? item in value) redactSecrets(item)];
  }
  return value;
}

Object? _maskValue(Object? value) {
  if (value == null) return null;
  if (value is String) return maskSecret(value);
  return '***';
}
