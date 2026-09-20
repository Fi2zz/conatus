# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

初始实现——技能加载，从 `deepseek-harness` 的 skill 包族移植为独立包：

- `SkillRegistry` / `provideSkillRegistry`（服务键 `'skillRegistry'`）：provider
  与运行时技能的注册表，`available` 是同步快照，收集串行化且带合并窗口；
  `inlineSkills` 允许把一段提示词直接当技能注册，不落盘也不解析 frontmatter
- `SkillProvider` 契约与 `SkillFilesystemProvider` / `provideSkillFilesystem`：
  从 `<项目根>/.conatus/skills`、`.agents/skills` 与用户目录发现
  `SKILL.md` / `<name>.md`，rank 100/200/300/400/500 决定同名遮蔽
- `parseSkillDocument`：真 YAML frontmatter，`name` / `description` 必需，
  `disable-model-invocation` 支持多种布尔写法；非法条目丢弃并告警
- `SkillCatalogSection` / `provideSkillCatalog`：把可用技能目录挂成 system prompt
  的 `skills` 段，空目录时完全不注册该段
- `SkillLoadTool` / `provideSkillTool`：`skill` 工具按名字返回 `<skill_content>`
  正文块，结果走 `tool/result` 事件
- `SkillRootWatcher`：为已存在的发现根起目录监听，变更合并成一次失效
- `SkillRegistry` 分层：`parent` + `visible` 组成子作用域，父级快照经谓词过滤后
  并入子级 `available`，同名由子级赢下并告警；父级变化级联到子级且不重跑子级
  provider；`load` 只认可见集合，被过滤的技能取不到
- 挂载点作用域化：`SkillCatalogSection.attach({name})` 换段名、
  `SkillLoadTool({name})` / `provideSkillTool({tools, name})` 换工具名与目标表，
  多个作用域得以共用一份 system prompt 与一张工具表
