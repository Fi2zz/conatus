# conatus_intent

> ⚠️ **实验性**：本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下
> 发生破坏性改动，请勿在生产环境依赖它。不进 `conatus` 伞包（`publish_to: none`），
> 使用方需显式依赖。

conatus 的意图路由：**先用正则和向量做本地意图匹配，命中就直接执行动作，不命中才走
完整 Agent Loop**。LLM 调用有延迟和成本，但高频请求（「开灯」「关灯」「设个闹钟」）
是固定模板，完全不需要模型。

| 请求类型 | 正则      | 向量      | LLM     |
| -------- | --------- | --------- | ------- |
| 固定命令 | ✅ 微秒级 | —         | —       |
| 同义表达 | —         | ✅ 毫秒级 | —       |
| 复杂请求 | —         | —         | ✅ 秒级 |

## 与相邻概念的区别

| 概念        | 管什么               | 层次            |
| ----------- | -------------------- | --------------- |
| **Intent**  | 用户意图的声明式路由 | Agent Loop 之前 |
| `skill`     | 过程性知识（怎么做） | Agent Loop 之内 |
| `goal`      | 长期目标             | 跨会话          |
| `plan_mode` | 本次任务的执行策略   | 单次任务        |

**Intent 是入口，Tool 是执行，Skill 是知识。** Intent 决定「走哪条路」，Skill 决定
「路上怎么做」。

## 用法

```dart
// 1) 装配：必须早于 provideAgentLoop——Agent Loop 在构造时读取 'router'
final IntentRouter router = provideIntentRouter(
  app,
  embedder: LocalEmbeddingProvider(),   // 可选；不配则只跑正则
);

// 2) 注册意图：正则命中即执行，零模型调用
router.register(Intent(
  name: 'light_on',
  description: '开灯',
  patterns: <Pattern>[RegExp(r'^(开灯|把灯打开)')],
  examples: <String>['亮一点', '太暗了'],       // 交给 embedder 生成嵌入
  priority: 10,
  action: const ToolAction(
    tool: 'device_control',
    argsTemplate: <String, Object?>{'device': 'light', 'op': 'on'},
  ),
));

// 3) 未命中自动落回完整 Agent Loop
final AgentLoop agent = provideAgentLoop(app, session: session);
await agent.run('你好');            // 命中：直接收口
await agent.run('帮我订张票');       // 未命中：走模型
```

从 JSON 加载（意图是数据，不是代码）：

```dart
await IntentLoader(
  router: router,
  handlers: <String, IntentHandler>{
    'morning': (RouteContext ctx) async => '早上好。今天 26 度，晴。',
  },
).loadFromFile(File('intents.json'));
```

离线端到端示例（无需 API Key）：`cd packages/conatus_intent && dart run example/demo.dart`。

## 动作类型

| `RoutedAction`   | 接进 Agent Loop 后        | 效果                                    |
| ---------------- | ------------------------- | --------------------------------------- |
| `DirectAction`   | `RouteReply`              | 直接收口，**零模型调用**                |
| `ToolAction`     | `RouteTools`              | 预置工具调用 → 执行 → 由模型收口        |
| `DelegateAction` | `RouteTools`（`skill` 工具） | 取回技能正文 → 由模型据此推理         |
| 未命中           | `RoutePass`               | 与没装路由器完全一致                    |

`DirectAction` 另有 `DirectAction.respond(text)` 静态回复构造；`ToolAction` 的
`argsTemplate` 支持 `{{input}}` / `{{state.<key>}}` 插值，`args` 闭包可覆盖它。

**JSON 往返**：`respond` / `tool` / `delegate` 三种声明式动作可序列化；由代码闭包构造
的动作（`DirectAction` 的执行体、`ToolAction.args`）序列化时抛
`IntentException('not-serializable')`——闭包本来就不是数据。非 `RegExp` 的模式同理。

## JSON 配置

```json
{
  "intents": [
    {
      "name": "light_on",
      "description": "开灯",
      "patterns": ["^(开灯|把灯打开|亮一点)"],
      "priority": 10,
      "action": { "type": "tool", "tool": "device_control",
                  "args": { "device": "light", "op": "on" } }
    },
    { "name": "morning_routine", "patterns": ["^(早上好|晨间播报)"],
      "action": { "type": "builtin", "handler": "morning_routine" } },
    { "name": "code_review", "patterns": ["^(审查代码|review code)"],
      "action": { "type": "delegate", "skill": "code-review" } },
    { "name": "thanks", "patterns": ["^(谢谢|thanks)"],
      "action": { "type": "respond", "text": "不客气。" } }
  ]
}
```

| type       | 对应动作         | 说明                    |
| ---------- | ---------------- | ----------------------- |
| `tool`     | `ToolAction`     | 调用工具                |
| `builtin`  | `DirectAction`   | 调用 `IntentLoader.handlers` 里的处理器 |
| `delegate` | `DelegateAction` | 经 `skill` 工具取回技能正文后交模型 |
| `respond`  | `DirectAction`   | 直接返回文本            |

## 嵌入

嵌入是独立的 seam，可替换为模型端点、构建时下发或本地实现：

- `LocalEmbeddingProvider`：纯 Dart 的字符 n-gram 哈希 + 余弦，离线、确定、零依赖。
  **它只认字形重叠，不认语义**：「把灯打开」与「开灯」高分，「亮一点」与「太暗了」
  不会。需要真正的同义表达匹配时用下面两种。
- `LlmEmbeddingProvider(EmbeddingLlm)`：把嵌入委托给模型端点。`EmbeddingLlm` 是本包
  定义的单方法端口，使用方自行接（如包一层豆包的 `POST /api/v3/embeddings`）——
  `conatus_llm` 的模型接入只有 chat / chatStream，没有嵌入能力。
- `Intent.embedding`：直接喂**预计算**嵌入（构建时或云端下发），运行时零嵌入请求。

`LocalEmbeddingProvider` 与预计算嵌入必须用同一套归一化，见
`normalizeForEmbedding`。

## 运行时 seam（全部可选注入）

| seam              | 用途                       | 缺省行为                       |
| ----------------- | -------------------------- | ------------------------------ |
| `embedder`        | 查询与示例嵌入             | 无嵌入，只用正则               |
| `tools`           | 意图动作调用工具           | 交给 Agent Loop 既有工具管线   |
| `telemetry`       | 埋点（缺省取 `ctx.telemetry`） | 无埋点                     |
| `session`         | 记录 `intent/routed` 事件  | 取会话存储里唯一打开的会话     |
| `skillRegistry`   | `DelegateAction` 取技能正文 | 由 `skill` 工具自己解析       |

埋点事件：`intent.registered` / `intent.unregistered` / `intent.matched` /
`intent.missed` / `intent.vector.failed` / `intent.embedding.failed`。

## 与 tools / skill 的结合

| 场景                | Intent 的角色                               |
| ------------------- | ------------------------------------------- |
| Skill 已沉淀为 Tool | `ToolAction` 直连，跳过 Agent 的推理        |
| Skill 是指令集      | `DelegateAction` 经 `skill` 工具加载后委托  |
| Skill 沉淀时        | `SkillIntentBridge.propose` 生成候选意图    |
| 部署时              | `ToolIntentGenerator.generate` 批量生成候选 |
| 运行时未命中        | 走 Agent Loop，`IntentLearner` 积累候选     |

`SkillIntentBridge` 与 `IntentLearner` 都**只产出候选，不自动注册**——模型生成的正则
可能过宽，放它自动进路由器会污染整个快路径。与 `conatus_skill`「启用前需审批」的口径
一致：`IntentCandidate.bind(action)` 绑上真实动作后，由人或部署方决定是否
`router.register`。

## 与 approval / tui 的协作

- **高危动作**：`DirectAction` 的执行体里自行取审批端口即可——意图命中只跳过推理，
  不跳过审批：

  ```dart
  action: DirectAction((RouteContext ctx) async {
    final Approval? approval = app.get<Approval>('approval');
    if (approval != null &&
        !await approval.request(ApprovalRequest(tool: 'unlock_door', ...))) {
      return '已取消';
    }
    return device.unlock();
  }),
  ```

- **路由可视化**：订阅 `router.changes`，`IntentMatched` 给出意图名 / 来源 / 置信度，
  `IntentMissed` 表示这一轮走了 Agent Loop。TUI 侧无需本包依赖 `conatus_tui`。

## 注意与限制

- **装配顺序**：`provideIntentRouter` 必须在 `provideAgentLoop` 之前调用。上下文里
  已有 `'router'` 时传 `fastPath: false` 只提供服务，不接线。
- **不修改 Agent Loop**：接线走 `conatus_agent` 已有的确定性路由 seam
  （`Router` / `RouteReply` / `RouteTools` / `RoutePass`），session 记录、取消传递、
  遥测全部沿用既有机制。
- **正则优先**：正则确定性高、零延迟，永远先跑；正则未命中才跑向量。
- **优先级决定顺序**：按 `priority` 降序，同 priority 按注册顺序（`orderByPriority`
  用原始下标做 tiebreaker，不依赖不稳定的 `List.sort`）。
- **未命中不阻塞**：向量匹配或嵌入生成失败时降级（跳过该意图 / 落回未命中），
  只埋点不抛错。嵌入失败会被缓存，不重试——提供者长期不可用时请重新注册意图。
- **命中不走 LLM**：命中一轮不产生 `llm/request` 事件；`RouteTools` 路径仍会调一次
  模型收口。
- 依赖方向：`conatus_intent → conatus_agent → conatus_llm → conatus_core`，反向不
  成立；`conatus_agent` 不依赖本包。
