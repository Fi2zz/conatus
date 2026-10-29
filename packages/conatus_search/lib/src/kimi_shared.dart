/// Kimi（Moonshot）Search / Fetch 两个端点共用的细节：凭据键、地址与请求头。
///
/// 两者同属 `POST <base>/v1/tools/` 下的只读接口，共用 `MOONSHOT_API_KEY` 与
/// OpenAI 兼容的错误体（解析在 `openai_compat.dart`）。Kimi 的模型接口同样用
/// 这个键，已把 Kimi 配成 LLM 的用户不需要再申请搜索凭据。
library;

import 'openai_compat.dart';

/// Kimi API Key 的凭据键名。
const String kKimiCredentialKey = 'MOONSHOT_API_KEY';

/// Kimi 默认 base URL。
const String kKimiBaseUrl = 'https://api.moonshot.cn';

/// Search / Fetch 共用的请求头。
Map<String, String> kimiHeaders(String apiKey) => <String, String>{
      'content-type': 'application/json',
      'authorization': 'Bearer $apiKey',
    };

/// 解析 JSON；非 JSON 返回 `null`，由调用方给出统一的错误文案。
Object? decodeKimiJson(String body) => decodeJsonBody(body);

/// 取出 Kimi 错误体里的 `error.message`，拼成 `：xxx` 后缀。
///
/// Kimi 用 400（参数不合法）、403（`security_risk` 风控拒绝）、404
/// （`markdown_not_found`）、429（限速）等区分原因，只报状态码会让人无从判断
/// 该换参数、该换链接还是该退避。解析不出时返回空串。
String kimiErrorDetail(String body) => openAiCompatErrorDetail(body);
