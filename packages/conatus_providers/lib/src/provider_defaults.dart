/// 内置默认提供商：常见 OpenAI 兼容平台。
///
/// 密钥经 [ProviderProfile.credentialKey] 从环境变量 / 凭据服务读取，因此这里
/// 可以无条件列出；未配置密钥的项在调用时才会报缺凭据。
library;

import 'provider_profile.dart';

/// 缺省提供商清单（首次运行时落盘为 providers.json）。
const List<ProviderProfile> kDefaultProviders = <ProviderProfile>[
  ProviderProfile(
    name: 'ark',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    credentialKey: 'ARK_API_KEY',
    models: <String>['doubao-seed-1-8-251228'],
    description: '火山方舟（豆包）',
  ),
  ProviderProfile(
    name: 'deepseek',
    baseUrl: 'https://api.deepseek.com',
    credentialKey: 'DEEPSEEK_API_KEY',
    models: <String>['deepseek-chat', 'deepseek-flash'],
    description: 'DeepSeek 官方',
  ),
  ProviderProfile(
    name: 'volcengine-coding-plan',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/coding/v3',
    credentialKey: 'ARK_API_KEY',
    models: <String>['doubao-seed-1-8-251228'],
    description: '火山方舟 Coding Plan',
  ),
  ProviderProfile(
    name: 'ark-agent-plan',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/plan/v3',
    credentialKey: 'ARK_API_KEY',
    models: <String>['doubao-seed-1-8-251228'],
    description: '火山方舟 Agent Plan',
  ),
];
