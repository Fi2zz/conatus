/// 内置的具体提供商：豆包与 DeepSeek，以及默认回退链。
///
/// 从 `conatus_llm` 迁出：`conatus_llm` 只保留通用 wire 层与回退机制，
/// 「有哪些具体提供商、各自的端点与默认模型」属于提供商管理（本包）。
library;

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_llm/conatus_llm.dart';

/// 豆包提供商。走火山引擎方舟的 OpenAI 兼容端点。
///
/// 默认端点 `https://ark.cn-beijing.volces.com/api/v3`，默认模型
/// `doubao-seed-1-8-251228`，凭据键 `ARK_API_KEY`（经注入的 [Credentials]
/// 解析，构造时需显式传 `apiKey` 或 `credentials` 实例）。
class DoubaoProvider extends OpenAiCompatibleProvider {
  DoubaoProvider({
    super.apiKey,
    String? baseUrl,
    String? model,
    super.apiStyle,
    super.userAgent,
    super.client,
    super.credentials,
    super.credentialKey = 'ARK_API_KEY',
    Duration? timeout,
  }) : super(
          name: 'doubao',
          baseUrl: baseUrl ?? 'https://ark.cn-beijing.volces.com/api/v3',
          model: model ?? 'doubao-seed-1-8-251228',
          timeout: timeout ?? const Duration(seconds: 60),
        );
}

/// DeepSeek 提供商。
///
/// 默认端点 `https://api.deepseek.com`，默认模型 `deepseek-flash`，凭据键
/// `DEEPSEEK_API_KEY`（经注入的 [Credentials] 解析）。
class DeepSeekProvider extends OpenAiCompatibleProvider {
  DeepSeekProvider({
    super.apiKey,
    String? baseUrl,
    String? model,
    super.apiStyle,
    super.userAgent,
    super.client,
    super.credentials,
    super.credentialKey = 'DEEPSEEK_API_KEY',
    Duration? timeout,
  }) : super(
          name: 'deepseek',
          baseUrl: baseUrl ?? 'https://api.deepseek.com',
          model: model ?? 'deepseek-flash',
          timeout: timeout ?? const Duration(seconds: 60),
        );
}

/// 默认回退链：豆包 → DeepSeek，任一成功即返回。
///
/// [credentials] 是 Key 的唯一来源（通常传 `provideCredentials(app)` 的结果）；
/// 不注入时缺少 Key 的调用会抛 [LlmException]。
FallbackLlm defaultFallbackLlm({
  Credentials? credentials,
  List<LlmProvider>? extra,
}) =>
    FallbackLlm(<LlmProvider>[
      DoubaoProvider(credentials: credentials),
      DeepSeekProvider(credentials: credentials),
      ...?extra,
    ]);
