# conatus_llm

conatus 的大模型接入：

- `LlmProvider` 契约（非流式 `chat` / 流式 `chatStream`，均支持原生 function calling）
- `FallbackLlm` 顺序回退链（任一提供商失败即尝试下一个）
- `OpenAiCompatibleProvider`：任意 OpenAI 兼容端点的通用实现（`LlmApiStyle.chat`
  与 `LlmApiStyle.responses`），本包**不含具体提供商**——豆包 / DeepSeek 的便捷类
  在 `conatus_code`（`lib/providers.dart`）
- Key 的解析：显式 `apiKey` → 注入的 `credentials`（`conatus_credentials`），
  **不直接读环境变量**；两者都没有时调用抛 `LlmException('缺少 API Key')`，
  并订阅 `changes` 做运行时轮换
- `LlmMessage.cacheable` 是本地前缀标记，**不写入请求体**，仅供消费方计算可缓存前缀
- 请求携带 `User-Agent`（默认 `ConatusCode/0.16`，可按 provider 自定义）

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
```
