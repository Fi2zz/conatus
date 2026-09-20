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

也可以完全不走磁盘，直接传一段提示词当技能：

```dart
await provideSkillRegistry(ctx, inlineSkills: <SkillRegistration>[
  const SkillRegistration(
    name: 'release-notes',                       // 必须 kebab-case
    description: '把一组合并记录改写成发布说明',   // 目录里显示的一行
    content: '先读 git log，再按 Keep a Changelog 组织。',
  ),
]);
provideSkillCatalog(ctx);
provideSkillTool(ctx);
```

`inlineSkills` 与文件系统技能进同一份目录、同一个 `skill` 工具，区别只在来源：
内联技能 `source` / `provider` 都是 `runtime`、rank 250（项目声明可以覆盖它，
它又压过自定义与用户目录），且恒为模型可见——`SkillRegistration` 没有
`disable-model-invocation` 对应字段。名字非法或描述为空时**在装配处**抛
`ArgumentError`，不会静默跳过。

- `SkillRegistry`（服务键 `'skillRegistry'`，`ctx.skillRegistry`）：provider 与
  运行时技能的集散地。`available` 是目录与工具读取的**同步快照**；
  `registerProvider` / `register` / `invalidate` 只标脏并调度一次收集（默认 50ms
  合并窗口），收集串行化，快照确有变化时经 `onChange` 通知。装配后再注册同样
  有效，只是要 `await registry.refresh()` 让快照立刻更新。
- `SkillProvider`（`list()` / `load(summary)`）：一类技能来源。单个 provider 抛错
  只降级它自己——其余 provider 的产出照常生效，错误经 `onWarning` 上报。
- `SkillRootWatcher`：为已存在的发现根起目录监听，变更在 250ms 窗口合并成一次
  `invalidate`；装配时就缺席的根不会被追认（后续创建的目录要等下一次重启）。
- `SkillCatalogSection`：目录为空时**不注册** `skills` 段——没有技能时 system
  prompt 与本插件不存在时逐字相同。

## 分层（作用域）

`SkillRegistry` 支持父子链：传了 `parent` 的注册表成为子作用域，它的 `available`
是父级快照与自己快照的合并结果——同名由子级赢下并告警，其余全部继承。

```dart
final Context child = ctx.plugin('scoped', (Context c) {});
final SkillRegistry scoped = SkillRegistry(
  parent: ctx.skillRegistry,
  visible: (SkillSummary s) => s.source == kSkillSourceProjectConatus,
);
await provideSkillRegistry(child, registry: scoped); // 遮蔽父级的 'skillRegistry'
```

- `visible` 谓词决定从父级继承哪些技能，`null` 表示全部继承。它**只约束继承来的
  条目**：本注册表自己注册的技能始终可见。
- 可见性是硬边界：被过滤掉的技能不出现在 `available` / `modelInvocable`，
  `load(name)` 也返回 `null`——模型无法绕过目录调用一个看不见的技能。
- 父级快照变化级联到子级：子级只重新合并已有的自身快照，不重跑自己的 provider。
- 这套分层与层内 rank 排序是两回事：rank（100–500 与 250）在**一个注册表内部**
  决定同名遮蔽，`parent` 决定**注册表之间**的合并。

挂载点必须跟着作用域化，否则会在同名检查处抛 `StateError`：

| 挂载点 | 隔离方式 |
|---|---|
| 目录段 | 换段名：`section.attach(name: 'skills-scoped')`；或用独立的 `SystemPrompt` |
| `skill` 工具 | 换工具名：`provideSkillTool(child, tools: scopedTools, name: 'skill-scoped')` |

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

- 分层是链式的：一个子注册表只认一个 `parent`，没有多父合并；同名覆盖是整条替换，
  没有字段级合并。
- 父级释放不会通知子级：父级 `dispose()` 不广播变更，还活着的子级会停在最后一次
  合并的快照上（正常用法里子级随同一个上下文树一起释放，不会走到这里）。
- 挂载点不自动作用域化：多个作用域共用一份 `SystemPrompt` / `ToolRegistry` 时，
  段名与工具名要显式换名，否则装配处抛 `StateError`。
- provider 没有取消信号：一次慢的 `list()` 会拖住这一轮收集（收集天然串行）。
- 只扫发现根一层，不递归 `**/SKILL.md`；发现根在装配时确定，之后不跟随工作目录。
- 本包只有模型侧入口：斜杠 `/skill:<技能名>` 由 `conatus_tui` 提供（它把技能投影成用户
  命令，`disable-model-invocation` 的技能由此手动触发）；直接用本包时，那类技能
  对模型完全不可见，也没有别的调用路径。
- 单个条目非法即整条丢弃，模型只能看到「不存在」。
- `metadata` 只做保留，不参与寻址或渲染。
