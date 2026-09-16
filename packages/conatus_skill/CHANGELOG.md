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
