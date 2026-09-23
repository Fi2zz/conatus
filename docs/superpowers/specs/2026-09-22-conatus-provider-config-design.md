# conatus provider 配置收敛 — 设计

日期：2026-09-22
状态：已确认，待实施
范围：`packages/conatus_code`（provider 装配与配置），不涉及 `conatus_search` / `conatus_llm` 的协议层

## 背景

conatus 的模型提供商配置目前分散在三套来源，Key 管理混乱：

1. **`providers.json`**（`<baseDir>/providers.json`）——`ProviderStore` 持久化的注册表，字段含 `apiKey`；
2. **`[credentials]` 表**（config.toml）——`ConfigCredentials` 读，模型与搜索 Key 混放；
3. **环境变量**——`EnvCredentials` 优先于 `[credentials]` 表。

用户诉求：**provider 定义（含 Key）统一收敛到 `~/.nava/config.toml` 一个文件的 `[providers.<名字>]` 表**，让 Key 只有一个地方管。

## 决策记录

| 决策点         | 结论                                                                                                                | 理由                                                                   |
| -------------- | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| 收敛程度       | **全收敛**：`[providers.xxx]` 是 provider 唯一来源；`providers.json` 废弃、模型 Key 不再走 `[credentials]`/环境变量 | 用户明确要求统一                                                       |
| oauth          | 字段**保留但不做调用**（解析记录，api_key 为空时提示）                                                              | conatus 无 OAuth2 基础设施，本期不做                                   |
| 内置默认       | **无**：config 没写 `[providers]` 就没有 provider                                                                   | 用户明确"没有内置情况"                                                 |
| type 语义      | **→ 请求形态**：`openai`→chat、`kimi`→responses，都走现有 OpenAI 兼容客户端                                         | kimi 端点已确认 OpenAI 兼容                                            |
| 非模型 Key     | `[credentials]` 表**保留**，专放搜索等非模型 Key                                                                    | 模型 Key 收敛后语义清晰                                                |
| 当前 provider  | `[llm] default_model = "provider/model"`（替代 `provider` + `model` 两个字段）                                      | 一个字段同时定 provider 与默认模型                                     |
| /provider 命令 | 退化为**只读展示** + `/model` 切换模型名                                                                            | 增删改直接编辑 config.toml，不在 Dart 里写回 TOML                      |
| 实现路径       | **A. config 驱动注册表**：`ProviderRegistry` 保留为运行时抽象，数据源换成 config                                    | 改动集中、可测；去掉注册表层需要重写 `/provider`/`buildLlm`/测试，不值 |

## 架构

### config.toml 格式（目标形态）

```toml
[providers.arkcli-agent-plan]
api_key = "ark-..."
base_url = "https://ark.cn-beijing.volces.com/api/plan/v3"
type = "openai"

[providers.deepseek]
api_key = "sk-..."
base_url = "https://api.deepseek.com/v1"
type = "openai"

[providers."managed:kimi-code"]
api_key = ""                                  # oauth 时留空
base_url = "https://api.kimi.com/coding/v1"
type = "kimi"
[providers."managed:kimi-code".oauth]
key = "oauth/kimi-code"
storage = "file"

[llm]
default_model = "arkcli-agent-plan/doubao-seed-2-0-lite-260215"

[credentials]                                 # 只放非模型 Key（搜索等）
TAVILY_API_KEY = "tvly-..."
```

- `[providers.<名字>]`：名字任意字符串；含 `.`/`:` 等 TOML 特殊字符时用引号（`"managed:kimi-code"`）。
- 每项字段：`api_key`（空串 = 无 Key）、`base_url`、`type`（`openai` / `kimi`，未知值抛配置错误）。
- `oauth` 子表：解析并记录 `key` / `storage`，**不实现 OAuth flow**；该 provider `api_key` 为空时启动提示「OAuth 未实现：请为 <name> 配置 api_key」。
- `[llm] default_model = "provider/model"`：**按第一个 `/` 拆**成 provider 名与默认模型名（模型名本身不含 `/`）。**替代** `[llm] provider` 与 `[llm] model` 两个字段（移除后者）。
- `[credentials]` 表行为不变（`ConfigCredentials`），只放搜索等非模型 Key（`TAVILY_API_KEY` / `BRAVE_API_KEY` / `FIRECRAWL_API_KEY`）。

### config schema（`lib/src/config/`）

```dart
/// provider 类型：决定请求形态。
enum ProviderType { openai, kimi }

class ProviderConfig {
  const ProviderConfig({
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.type = ProviderType.openai,
    this.oauthKey,
  });
  final String name;
  final String baseUrl;
  final String apiKey;
  final ProviderType type;
  final String? oauthKey;   // oauth 子表的 key；保留不调用
}

class LlmConfig {
  const LlmConfig({this.defaultModel});
  final String? defaultModel;   // "provider/model"
}

class ConatusCodeConfig {
  // 新增：有序的 [providers.<name>] 表
  final List<ProviderConfig> providers;
  final LlmConfig llm;
  // ... 其余段不变
}
```

`ProviderType` → `LlmApiStyle` 映射：`openai` → `chat`、`kimi` → `responses`（在解析 `[providers]` 时完成，`ProviderProfile.apiStyle` 直接存映射结果）。

### provider 装配（`lib/src/tui/tui_app.dart`）

- `ConatusTuiRuntime.create` 移除 `providers`（bool）与 `providersFile` 形参，新增 `List<ProviderConfig>? providers`（config 解析结果；null = 不装配）。
- 装配时把 `config.providers` 转成 `List<ProviderProfile>`（`name` / `baseUrl` / `apiKey` / `apiStyle` 映射），注入 `ProviderRegistry`；**不再** `ProviderStore(path: ...)` + `load()`。
- `[llm] default_model` 解析出 provider 名与默认模型名：`registry.buildLlm(providerName, model: modelName)`；`/model` 命令只切模型名、保持当前 provider。
- `bin/conatus_code.dart`：把 `config.llm.defaultModel` 拆分后传给 `create`；`providers: config.providers`。

### 移除项

| 项                                                                                  | 处理                                                                                     |
| ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `lib/src/providers/provider_store.dart`（`ProviderStore` / `ProviderSnapshot`）     | 删除（providers.json 读写）                                                              |
| `lib/src/providers/provider_defaults.dart`（`kDefaultProviders`）                   | 删除（内置默认清单）                                                                     |
| `lib/src/providers/provider_import.dart`（registry 导入）                           | 删除（`/provider` 不再导入）                                                             |
| `lib/src/providers/provider_registry.dart`                                          | **保留**（`add`/`remove`/`select` 等可删，`profiles`/`byName`/`buildLlm`/`hasKey` 保留） |
| `lib/src/providers/builtin_providers.dart`（`DoubaoProvider` / `DeepSeekProvider`） | **保留**（example 在用，作便捷类）                                                       |
| `/provider` 命令的增删改查（`tui_controller_provider.dart`）                        | 移除，退化为只读展示（列表 + 当前项）                                                    |

### 错误处理

| 场景                                             | 行为                                                                               |
| ------------------------------------------------ | ---------------------------------------------------------------------------------- |
| config 无 `[providers]` 或 `[llm] default_model` | 启动报错：`请在 config.toml 配置 [providers.xxx] 与 [llm] default_model`           |
| `default_model` 的 provider 名不在 `[providers]` | 报错：`未知提供商：<name>（config.toml [providers] 里没有）`                       |
| provider 配了 oauth 但 `api_key` 为空            | 启动提示：`OAuth 未实现：请为 <name> 配置 api_key`（该 provider 不可用，其余照常） |
| `type` 未知                                      | `ConfigException`（沿用现有报错格式）                                              |

## 数据流

```
config.toml
  → loadConfig()（config_parser 解析 [providers.*] / [llm] default_model）
  → ConatusTuiRuntime.create(providers: config.providers, defaultModel: ...)
      → ProviderProfile 列表 → ProviderRegistry
      → buildLlm(providerName, model: modelName) → LlmProvider
  → /provider（只读列出）· /model（切模型名）
```

## 破坏性变更（用户侧）

- `providers.json` 不再读写：已有 `providers.json` 的用户需把 provider 定义（含 `apiKey`）迁移到 config.toml 的 `[providers.xxx]`；`<baseDir>/providers.json` 遗留文件可删。
- `[llm] provider` / `[llm] model` 两个字段被 `[llm] default_model = "provider/model"` 替代。
- `/provider` 命令不再支持 `add` / `remove` / 导入；增删改走 config.toml 编辑。
- `ConatusTuiRuntime.create` 的 `providers`（bool）/ `providersFile` 形参移除，新增 `providers`（列表）与 `defaultModel`。

## 测试计划

| 文件                                              | 覆盖                                                                                            |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `test/config/config_loader_test.dart`（扩充）     | `[providers.*]` 解析（含引号名字、type 映射、oauth 子表）、`default_model` 拆分、未知 type 报错 |
| `test/tui/tui_provider_command_test.dart`（重写） | `/provider` 只读展示（列表 + 当前项）、`/model` 切模型名                                        |
| `test/tui/tui_model_view_test.dart`（适配）       | 装配从 config 构造、无 provider 报错                                                            |
| 删除                                              | `provider_store_test`（若有）、`provider_registry_test` 的增删改用例                            |

## 后续（不在本 spec 内）

- OAuth flow（kimi-code 等）：需 OAuth2 客户端 + token 存储/刷新，接入 `conatus_credentials` 的存储层。
- `default_model` 的多模型列表 / `/model` 自动补全候选。
