/// OpenAI 兼容错误体的解析：DeepSeek / Kimi 等厂商的只读工具接口共用。
///
/// 这些厂商的错误体形状一致（`{"error": {"message": ..., "type": ...}}`），
/// 但源名不同。放在这里让各源的 shared 文件只声明自己的键与地址，不再各写一份
/// 解析、也不再出现「kimi 的错误体按 deepseek 的规则解析」这种名字错位。
library;

import 'dart:convert';

/// 解析 JSON；非 JSON 返回 `null`，由调用方给出统一的错误文案。
Object? decodeJsonBody(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

/// 从 OpenAI 兼容错误体里取出 `error.message`，拼成 `：xxx` 后缀。
///
/// 上游用 4xx 里不同的 `error.message` 说明原因（余额不足、限速、URL 不安全、
/// 取不到正文…），只报状态码会让人无从判断该充值、该退避还是该换链接。解析不出
/// 时返回空串，不影响既有文案。
String openAiCompatErrorDetail(String body) {
  final Object? error = switch (decodeJsonBody(body)) {
    final Map<String, Object?> map => map['error'],
    _ => null,
  };
  final Object? message = switch (error) {
    final Map<String, Object?> map => map['message'],
    _ => null,
  };
  return message is String && message.isNotEmpty ? '：$message' : '';
}
