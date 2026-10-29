/// DeepSeek Search / Fetch 两个端点共用的细节：凭据键、JSON 解码与错误提取。
///
/// 两者同属 `<base>/v1/tools/` 下的只读接口，共用 `DEEPSEEK_API_KEY` 与
/// OpenAI 兼容的错误体，放在一处避免两份解析各自漂移。
library;

import 'dart:convert';

/// DeepSeek API Key 的凭据键名。
///
/// 与 `conatus_code` 的 DeepSeek LLM 用同一个键：已经把 DeepSeek 配成模型的
/// 用户不需要额外申请凭据。
const String kDeepSeekCredentialKey = 'DEEPSEEK_API_KEY';

/// DeepSeek 默认 base URL。
const String kDeepSeekBaseUrl = 'https://api.deepseek.com';

/// Search / Fetch 共用的请求头。
Map<String, String> deepSeekHeaders(String apiKey) => <String, String>{
      'content-type': 'application/json',
      'authorization': 'Bearer $apiKey',
    };

/// 解析 JSON；非 JSON 返回 `null`，由调用方给出统一的错误文案。
Object? decodeDeepSeekJson(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

/// 从 OpenAI 兼容错误体里取出 `error.message`，拼成 `：xxx` 后缀。
///
/// 上游用 402（余额不足）、429（限速）这类状态码区分原因，只报状态码会让人
/// 无从判断该充值还是该退避。解析不出时返回空串，不影响既有文案。
String deepSeekErrorDetail(String body) {
  final Object? error = switch (decodeDeepSeekJson(body)) {
    final Map<String, Object?> map => map['error'],
    _ => null,
  };
  final Object? message = switch (error) {
    final Map<String, Object?> map => map['message'],
    _ => null,
  };
  return message is String && message.isNotEmpty ? '：$message' : '';
}
