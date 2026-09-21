/// 测试助手：以通用 `OpenAiCompatibleProvider` 复刻内置提供商的默认配置。
///
/// `DoubaoProvider` / `DeepSeekProvider` 已迁往 `conatus_providers`（不能反向
/// 依赖）；wire 层测试用这两个 helper 保持原默认端点 / 模型 / 凭据键。
library;

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:http/http.dart' as http;

/// 豆包形态的测试 provider。
OpenAiCompatibleProvider doubaoProviderForTest({
  String? apiKey,
  String? baseUrl,
  String? model,
  LlmApiStyle apiStyle = LlmApiStyle.chat,
  String? userAgent,
  http.Client? client,
  Credentials? credentials,
  String credentialKey = 'ARK_API_KEY',
  Duration? timeout,
}) =>
    OpenAiCompatibleProvider(
      name: 'doubao',
      baseUrl: baseUrl ?? 'https://ark.cn-beijing.volces.com/api/v3',
      model: model ?? 'doubao-seed-1-8-251228',
      apiStyle: apiStyle,
      userAgent: userAgent ?? kDefaultLlmUserAgent,
      credentialKey: credentialKey,
      apiKey: apiKey,
      client: client,
      credentials: credentials,
      timeout: timeout ?? const Duration(seconds: 60),
    );

/// DeepSeek 形态的测试 provider。
OpenAiCompatibleProvider deepseekProviderForTest({
  String? apiKey,
  String? baseUrl,
  String? model,
  LlmApiStyle apiStyle = LlmApiStyle.chat,
  String? userAgent,
  http.Client? client,
  Credentials? credentials,
  String credentialKey = 'DEEPSEEK_API_KEY',
  Duration? timeout,
}) =>
    OpenAiCompatibleProvider(
      name: 'deepseek',
      baseUrl: baseUrl ?? 'https://api.deepseek.com',
      model: model ?? 'deepseek-flash',
      apiStyle: apiStyle,
      userAgent: userAgent ?? kDefaultLlmUserAgent,
      credentialKey: credentialKey,
      apiKey: apiKey,
      client: client,
      credentials: credentials,
      timeout: timeout ?? const Duration(seconds: 60),
    );
