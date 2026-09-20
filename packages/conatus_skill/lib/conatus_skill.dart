/// 技能加载：从 `.conatus/skills` 与 `.agents/skills` 发现 `SKILL.md` 形式的
/// 指令集，把可调用技能目录注入 system prompt，并由 `skill` 工具按需把正文
/// 加载进对话。
///
/// 技能 = 一段 Markdown 指令 + 一份 frontmatter（`name` / `description` /
/// `whenToUse` / `metadata` / `disable-model-invocation`）。模型先看到目录
/// （名字 + 一行描述），需要时调用 `skill` 工具取回正文；工具结果由 Agent Loop
/// 正常写进 `tool/result` 事件，因此「模型可见即已记录」无需额外机制。
/// 目录本身是运行时现场装配的 system prompt 段，没有技能时该段不存在。
///
/// ```dart
/// // 从磁盘发现
/// final SkillRegistry registry = await provideSkillRegistry(ctx);
/// provideSkillCatalog(ctx);
/// provideSkillTool(ctx);
/// await provideSkillFilesystem(ctx);
///
/// // 或者直接把一段提示词当技能（不落盘）
/// await provideSkillRegistry(ctx, inlineSkills: <SkillRegistration>[
///   SkillRegistration(name: 'release-notes', description: '…', content: '…'),
/// ]);
/// ```
///
/// 技能来自磁盘时是「Markdown + frontmatter」，来自 [SkillRegistration] 时是
/// 「名字 + 描述 + 正文」；两条来源进同一份目录、同一个 `skill` 工具。
///
/// 注册表支持分层：`SkillRegistry(parent:, visible:)` 的子作用域继承父级技能、
/// 同名覆盖，父级变化级联。挂载点要跟着作用域化——目录段用
/// `SkillCatalogSection.attach(name:)` 换段名，工具用 `SkillLoadTool(name:)` 或
/// `provideSkillTool(..., name:)` 换名，否则装配处抛 `StateError`。
///
/// 服务键 `'skillRegistry'`（`ctx.skillRegistry`）。名称与 `conatus_agent` 的
/// `SkillLibrary`（`'skill'`，把重复工具序列沉淀成新工具）刻意区分。
library;

export 'src/skill.dart'
    show
        SkillRegistryContext,
        provideSkillCatalog,
        provideSkillFilesystem,
        provideSkillRegistry,
        provideSkillTool;
export 'src/skill_catalog.dart'
    show
        escapeSkillText,
        kSkillCatalogDescriptionMaxLength,
        kSkillCatalogInstruction,
        kSkillCatalogIntro,
        normalizeSkillDescription,
        renderSkillCatalog;
export 'src/skill_catalog_section.dart'
    show
        SkillCatalogSection,
        kSkillCatalogSectionName,
        kSkillCatalogSectionOrder;
export 'src/skill_collect.dart' show collectSkillSummaries;
export 'src/skill_content.dart'
    show escapeSkillAttribute, renderSkillContent, renderSkillResourceHint;
export 'src/skill_filesystem_provider.dart'
    show SkillFilesystemProvider, SkillRoot, defaultSkillRoots, findProjectRoot;
export 'src/skill_filesystem_watch.dart' show SkillRootWatcher;
export 'src/skill_markdown.dart'
    show
        SkillDocument,
        SkillFrontmatter,
        kSkillLegacyFrontmatterKeys,
        parseSkillDocument;
export 'src/skill_provider.dart' show SkillProvider, SkillProviderException;
export 'src/skill_ranking.dart' show SkillCandidateBatch, rankSkillCandidates;
export 'src/skill_refresh.dart' show SkillCollector;
export 'src/skill_registry.dart' show SkillRegistry;
export 'src/skill_scope.dart' show SkillVisibility, mergeScopedSummaries;
export 'src/skill_tool.dart' show SkillLoadTool, kSkillToolName;
export 'src/skill_types.dart'
    show
        SkillCandidate,
        SkillDefinition,
        SkillDirectoryResource,
        SkillOpaqueResource,
        SkillRegistration,
        SkillResourceBase,
        SkillSummary,
        SkillUrlResource,
        isSkillName,
        kSkillFilesystemProvider,
        kSkillRuntimeProvider,
        kSkillRuntimeRank,
        kSkillSourceCustom,
        kSkillSourceProjectAgents,
        kSkillSourceProjectConatus,
        kSkillSourceRuntime,
        kSkillSourceUserAgents,
        kSkillSourceUserConatus;
