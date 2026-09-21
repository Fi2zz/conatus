# conatus_providers

conatus 的模型提供商管理：`ProviderProfile` 注册表、JSON 持久化、自定义 registry
导入，以及按 profile 构造 OpenAI 兼容 `LlmProvider`。**不含 UI** —— TUI 的
`/provider` 命令在 `conatus_tui`。

## 接线

```dart
import 'package:conatus_providers/conatus_providers.dart';

final ProviderRegistry registry = provideProviders(
  app,
  store: ProviderStore(path: '.conatus/providers.json'),
);
await registry.load(); // 无文件时落盘内置默认
final LlmProvider? llm = registry.buildLlm(registry.currentName ?? '');
```

## 概念

- **`ProviderProfile`**：`name` / `baseUrl` / `credentialKey` / `models` /
  `apiStyle`（chat / responses）/ `userAgent`。**密钥不进配置**：`credentialKey`
  指向环境变量或 `conatus_credentials` 里的键名，由 LLM provider 构造期解析；
  `userAgent` 可空，缺省 `ConatusCode/0.16`，可设成其他 harness 客户端的 UA
  （如 `dsh/0.1.2`）以通过 plan 端点的客户端校验。
- **`ProviderRegistry`**（服务键 `'providers'`）：增删改查、当前选中、`load`
  落盘、`importRegistry` 合并、`buildLlm` 按 profile 构造提供商。
- **持久化**：`.conatus/providers.json` → `{"current": "...", "providers": [...]}`；
  文件缺失或损坏时回落到内置默认。
- **registry 导入**：GET `api.json`（带 `Authorization: Bearer <token>`），正文
  接受 `{"providers": [...]}` 或顶层数组，字段同 `ProviderProfile`。

## 内置默认

首次运行（无 providers.json）落盘四个常见平台：火山方舟 `api/v3`、DeepSeek
官方、火山方舟 Coding Plan（`api/coding/v3`）、Agent Plan（`api/plan/v3`）。
未配置密钥的项仍会列出，调用时才报缺凭据。

**Plan 端点只认订阅后生成的专属 Key**：`ark-agent-plan` 用
`ARK_AGENT_PLAN_API_KEY`、`volcengine-coding-plan` 用 `ARK_CODING_PLAN_API_KEY`，
普通方舟 Key（`ARK_API_KEY`）对 plan 端点会返回 401。
