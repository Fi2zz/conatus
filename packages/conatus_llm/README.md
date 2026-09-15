# conatus_llm

conatus 的大模型接入：

- `LlmProvider` 契约（非流式 `chat` / 流式 `chatStream`）
- `FallbackLlm` 顺序回退链（任一提供商失败即尝试下一个）
- `DoubaoProvider` / `DeepSeekProvider`（`LlmApiStyle.chat` 与 `LlmApiStyle.responses`）

环境变量：`ARK_API_KEY`（豆包，首选）、`DEEPSEEK_API_KEY`（DeepSeek，备选）。

```dart
import 'package:conatus_llm/conatus_llm.dart';

final llm = FallbackLlm.withDefaults();
final result = await llm.chat(<LlmMessage>[const LlmMessage('user', '你好')]);
print(result.content);
```
