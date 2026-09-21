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
    // 见 Coding Plan 支持模型（文档 + 控制台）；`ark-code-latest` 在控制台切模型。
    models: <String>[
      'ark-code-latest',
      'doubao-seed-evolving',
      'doubao-seed-2-1-turbo-260628',
      'doubao-seed-2-0-lite-260215',
      'deepseek-v4-pro',
      'deepseek-v4-flash',
      'glm-latest',
      'glm-5-3-flash',
      'kimi-k3',
      'kimi-k2-8-preview',
      'kimi-k2-7-code',
      'minimax-m3',
    ],
    description: '火山方舟 Coding Plan',
  ),
  ProviderProfile(
    name: 'ark-agent-plan',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/plan/v3',
    credentialKey: 'ARK_API_KEY',
    // 见 Agent Plan 支持模型（仅文本生成；图片/视频/语音模型不入列表）。
    models: <String>[
      'doubao-seed-evolving',
      'doubao-seed-2-1-turbo-260628',
      'doubao-seed-2-0-lite-260215',
      'doubao-seed-2-0-mini-260215',
      'deepseek-v4-1-flash',
      'deepseek-v4-pro',
      'deepseek-v4-flash',
      'glm-latest',
      'glm-5-3-flash',
      'kimi-k3',
      'kimi-k2-8-preview',
      'kimi-k2-7-code',
      'minimax-m3',
    ],
    description: '火山方舟 Agent Plan',
  ),
];
