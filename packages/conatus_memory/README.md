# conatus_memory

conatus 的**记忆写入策略**能力：一轮对话结束后，决定这段内容值不值得进入长期记忆。

它只管策略（保留判定）与挂载，**不管存储**——长期记忆的存 / 召回 / 遗忘 / 容量
仍在 `conatus_foundation` 的 `MemoryStore`。这样做的原因很直接：无差别写入会把
问候语和寒暄灌满记忆库，召回时全是噪声；而「什么值得记」是产品判断，不该长在
存储机制或 Agent Loop 里。

## 用法

```dart
provideMemory(ctx);          // 存储机制（foundation）
provideMemoryRecorder(ctx);  // 写入策略（本包）：agentLoop 出现即挂上
provideAgentLoop(ctx);       // 顺序无关：依赖齐备时自动激活
```

也可以直接控制判定：

```dart
final MemoryRecorder recorder = MemoryRecorder(memory: memory);
await recorder.beginTurn('项目用 Dart 还是 Kotlin？');
await recorder.endTurn(result: '这个项目使用 Dart 语言。');
```

自定义策略实现 `MemoryWritePolicy` 即可替换：

```dart
class OnlyDecisions implements MemoryWritePolicy {
  @override
  MemoryWriteDecision review({
    required String userInput,
    required String reply,
    required Iterable<MemoryEntry> existing,
  }) =>
      reply.contains('决定')
          ? MemoryWriteDecision.store(reply)
          : const MemoryWriteDecision.skip(MemoryWriteVerdict.rejected);
}
```

## 默认规则（`PolicyMemoryWritePolicy`）

按顺序判定，命中即停：

| 顺序 | 规则 | 判定 |
|------|------|------|
| 1 | 回复为空 | `emptyReply` |
| 2 | 输入是寒暄 / 确认（`你好` / `hello` / `谢谢` …） | `greeting` |
| 3 | 回复短于 `minReplyChars`（默认 12） | `shortReply` |
| 4 | 与已有条目字符 bigram Jaccard ≥ `duplicateThreshold`（默认 0.6） | `duplicate` |
| 5 | 其余写入，正文截断到 `maxChars`（默认 600） | `store` |

写入正文固定为两行：`用户：…\n助手：…`，标签 `conversation`。

三个阈值都可以在构造时覆盖，寒暄词表也可替换。

## 失败语义

| 场景 | 行为 |
|------|------|
| 轮次失败（`endTurn(error:)`） | 不写 |
| 未开始轮次就结束 | 不写 |
| 存储后端抛错 | **吞掉**（fail-open）：记忆是尽力而为，不能影响当轮结果 |
| 策略判定为不写 | 不写，`onStore` 仍收到判定原因 |

## 与 TaskCenter 的关系

两者都订阅 `AgentLoop.addTurnTracker`，互不知情、注册顺序无关、各自随上下文
释放自动摘除。Agent Loop 只保留一个公开钩子，不感知任何具体能力。
