# conatus_llm

conatus 的大模型接入：

- `LlmProvider` 契约（非流式 `chat` / 流式 `chatStream`，均支持原生 function calling）
- `FallbackLlm` 顺序回退链（任一提供商失败即尝试下一个）
- `OpenAiCompatibleProvider`：任意 OpenAI 兼容端点的通用实现（`LlmApiStyle.chat`
  与 `LlmApiStyle.responses`），本包**不含具体提供商**——豆包 / DeepSeek 的便捷类
  在 `conatus_code`（`lib/providers.dart`）
- `AnthropicProvider`：Anthropic Messages（`LlmApiStyle.anthropic`，`/messages`），
  支持 system 抽取、工具调用/结果、图片与 SSE 文本/thinking 增量；认证按主机区分
  （`opencode.ai` 用 `Authorization: Bearer`，其它主机用 `x-api-key`）。
  可缓存前缀（`LlmMessage.cacheable`）与最后一个工具会自动带
  `cache_control: ephemeral`；thinking 块的 `signature` 随 `LlmResult` /
  `LlmMessage.thinkingBlocks` 往返，供 tool loop 回传
- Key 的解析：显式 `apiKey` → 注入的 `credentials`（`conatus_credentials`），
  **不直接读环境变量**；两者都没有时调用抛 `LlmException('缺少 API Key')`，
  并订阅 `changes` 做运行时轮换
- `LlmMessage.cacheable` 是本地前缀标记，**不写入请求体**，仅供消费方计算可缓存前缀
- 请求携带 `User-Agent`（默认 `nava/0.1.0`，可按 provider 自定义）；可传 `headersProvider` 每次请求重算附加头（如 `x-opencode-session`）

```dart
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_llm/conatus_llm.dart';

final llm = OpenAiCompatibleProvider(
  name: 'my-endpoint',
  baseUrl: 'https://my-endpoint.example/v1',
  model: 'my-model',
  apiKey: 'sk-...',                       // 或 credentials: myCredentials
  userAgent: 'dsh/0.1.2',                 // 可选，伪装其他 harness 客户端
);
final result = await llm.chat(<LlmMessage>[const LlmMessage('user', '你好')]);
print(result.content);

// Anthropic Messages
final claude = AnthropicProvider(
  name: 'anthropic',
  baseUrl: 'https://api.anthropic.com/v1',
  model: 'claude-haiku-5-5',
  apiKey: 'sk-ant-...',
);
```
