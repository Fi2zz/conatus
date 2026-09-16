# conatus_skill

conatus 的技能加载：从 `.conatus/skills` 与 `.agents/skills` 发现 `SKILL.md`
形式的指令集，把可调用技能目录注入 system prompt，并由 `skill` 工具按需把正文
加载进对话。只依赖 `conatus_core`、`conatus_foundation` 与 YAML 解析库 `yaml`。

技能 = 一段 Markdown 指令 + 一份 frontmatter。模型先看到目录（名字 + 一行
描述），需要时调用 `skill` 工具取回正文；正文进了对话历史，就等于进了
`tool/result` 事件，因此「模型可见即已记录」不需要额外机制。

> 与 `conatus_agent` 的 `SkillLibrary`（服务键 `'skill'`，`ctx.skills`）**不是**
> 同一件事：那是「把反复出现的工具序列沉淀成一个新工具」，本包是「按需加载
> 一段指令」。两者的服务键、类型名与文档章节都刻意区分。

## 技能文件

发现根按 rank 从小到大依次生效（同名技能由 rank 小的赢下，被遮蔽的会告警）：

| rank | 来源 | 路径 |
|---|---|---|
| 100 | `project-conatus` | `<项目根>/.conatus/skills` |
| 200 | `project-agents` | `<项目根>/.agents/skills` |
| 300 | `custom` | 调用方传入的 `SkillRoot` |
| 400 | `user-conatus` | `$CONATUS_HOME/skills`（缺省 `~/.conatus/skills`） |
| 500 | `user-agents` | `$CONATUS_AGENTS_HOME/skills`（缺省 `~/.agents/skills`） |

项目根是最近的含 `.git` 的祖先目录，找不到时用当前工作目录。每个根只扫**一层**：
目录束 `<root>/<name>/SKILL.md`，或平铺文件 `<root>/<name>.md`；其它条目跳过。

用 `SkillRegistry.register` 注册的运行时技能以 rank 250 参与同一排序——项目声明
可以覆盖它，它又压过自定义目录与用户目录。

frontmatter 用真 YAML，夹在首行与闭合行的 `---` 之间：

```markdown
---
name: release-notes
description: 把一组合并记录改写成发布说明
whenToUse: 用户提到发布说明、changelog 时
metadata:
  owner: platform
---

正文：模型调用 `skill` 时会原样看到这些指令。
```

- `name`（必需）：`^[a-z0-9]+(?:-[a-z0-9]+)*$`，模型用它寻址；
- `description`（必需）：非空，目录里只出现它的一行；
- `whenToUse`、`metadata`：可选；
- `disable-model-invocation`（可选布尔）：为真时该技能不出现在目录与 `skill`
  工具里（本包没有用户侧入口，因此等于对模型完全隐藏）。布尔值接受
  `true/false`、`yes/no`、`on/off`、`1/0`，大小写不敏感；
- 旧 camelCase 键（`disableModelInvocation` / `modelInvocable` / `userInvocable`）
  会让整个条目被丢弃并告警，而不是被忽略。

解析失败、名字非法、缺 `description` 的条目一律丢弃并告警——目录里出现的东西
一定是可以加载的；反过来，模型也无法区分「技能不存在」与「技能文件非法」。

## 装配

```dart
final SkillRegistry registry = await provideSkillRegistry(ctx);
provideSkillCatalog(ctx);            // 目录段：有技能才挂
provideSkillTool(ctx);               // 注册 skill 工具
await provideSkillFilesystem(ctx);   // 发现 .conatus/skills 等目录并监听变更
```

- `SkillRegistry`（服务键 `'skillRegistry'`，`ctx.skillRegistry`）：provider 与
  运行时技能的集散地。`available` 是目录与工具读取的**同步快照**；
  `registerProvider` / `register` / `invalidate` 只标脏并调度一次收集（默认 50ms
  合并窗口），收集串行化，快照确有变化时经 `onChange` 通知。
- `SkillProvider`（`list()` / `load(summary)`）：一类技能来源。单个 provider 抛错
  只降级它自己——其余 provider 的产出照常生效，错误经 `onWarning` 上报。
- `SkillRootWatcher`：为已存在的发现根起目录监听，变更在 250ms 窗口合并成一次
  `invalidate`；装配时就缺席的根不会被追认（后续创建的目录要等下一次重启）。
- `SkillCatalogSection`：目录为空时**不注册** `skills` 段——没有技能时 system
  prompt 与本插件不存在时逐字相同。

## 模型可见

- 目录段是运行时现场装配的 system prompt 的一部分（与 `persona` 段同构），
  它不进会话事件流，也不参与 `deriveAgentMessages`；「模型可见即已记录」不变式
  明确把这类现场装配排除在校验之外。
- `skill` 工具的结果是普通工具结果，由 Agent Loop 写进 `tool/result` 事件。
- 目录只包含名字与被截断（缺省 500 字符）的描述，不含 `whenToUse`、来源与正文；
  正文只有真正调用工具时才会进入对话。
- 改正文不会改变目录内容，模型不会因此收到任何通知（目录只在名字、描述、
  来源或路径变化时更新）。

## 限制

- 只有一层全局注册表，没有 per-scope 分层；同名遮蔽发生在整个可见范围内。
- provider 没有取消信号：一次慢的 `list()` 会拖住这一轮收集（收集天然串行）。
- 只扫发现根一层，不递归 `**/SKILL.md`；发现根在装配时确定，之后不跟随工作目录。
- 只做模型侧调用，没有斜杠 `/name` 直接调用；`disable-model-invocation` 的技能
  因此对模型完全不可见。
- 单个条目非法即整条丢弃，模型只能看到「不存在」。
- `metadata` 只做保留，不参与寻址或渲染。
