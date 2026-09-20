/// 技能插件装配：注册表、目录发现、system prompt 目录段与 `skill` 工具。
///
/// ```dart
/// final registry = await provideSkillRegistry(ctx);
/// provideSkillCatalog(ctx);          // 有技能才挂 PromptSection
/// provideSkillTool(ctx);             // 注册 skill 工具
/// await provideSkillFilesystem(ctx); // 发现 .conatus/skills 等目录并起监听
/// ```
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'skill_catalog.dart';
import 'skill_catalog_section.dart';
import 'skill_filesystem_provider.dart';
import 'skill_filesystem_watch.dart';
import 'skill_provider.dart';
import 'skill_registry.dart';
import 'skill_tool.dart';
import 'skill_types.dart';

/// `ctx.skillRegistry`：当前上下文可见的技能注册表。
///
/// 与 `conatus_agent` 的 `ctx.skills`（技能沉淀库）不是同一件事：这里是「按需
/// 加载一段指令」，那边是「把重复的工具序列沉淀成新工具」。
extension SkillRegistryContext on Context {
  /// 取当前上下文可见的 [SkillRegistry]（未提供时抛 [StateError]）。
  SkillRegistry get skillRegistry => require<SkillRegistry>('skillRegistry');
}

/// 提供服务键 `'skillRegistry'`，注册 [providers] 与 [inlineSkills] 并完成首次收集。
///
/// [inlineSkills] 是「直接把一段提示词当技能用」的入口：不落盘、不解析
/// frontmatter，只要求 kebab-case 名字与非空描述。需要自定义合并窗口或告警出口
/// 时，传一个自己构造的 [registry]。
///
/// 子作用域同样走 [registry]：传一个 `SkillRegistry(parent: ..., visible: ...)`
/// 进来，本函数会把它提供为当前上下文的 `'skillRegistry'`，遮蔽父级的注册表。
///
/// 注册表的生命周期随 [ctx]：上下文释放时取消待执行的收集并清空监听。
Future<SkillRegistry> provideSkillRegistry(
  Context ctx, {
  Iterable<SkillProvider> providers = const <SkillProvider>[],
  Iterable<SkillRegistration> inlineSkills = const <SkillRegistration>[],
  SkillRegistry? registry,
}) async {
  final SkillRegistry resolved = registry ?? SkillRegistry();
  ctx.provide('skillRegistry', resolved);
  ctx.onDispose(resolved.dispose);
  for (final SkillProvider provider in providers) {
    ctx.effect(() => resolved.registerProvider(provider));
  }
  for (final SkillRegistration registration in inlineSkills) {
    ctx.effect(() => resolved.register(registration));
  }
  await resolved.refresh();
  return resolved;
}

/// 注册目录发现型 provider，并（默认）为已存在的发现根起目录监听。
///
/// [roots] 缺省用 [defaultSkillRoots]（项目根 + 用户目录）；监听期间的变更在
/// [debounce] 窗口合并成一次重新收集。
Future<SkillFilesystemProvider> provideSkillFilesystem(
  Context ctx, {
  List<SkillRoot>? roots,
  bool watch = true,
  Duration debounce = const Duration(milliseconds: 250),
}) async {
  final SkillRegistry registry = ctx.require<SkillRegistry>('skillRegistry');
  final SkillFilesystemProvider provider = SkillFilesystemProvider(
    roots: roots ?? defaultSkillRoots(),
    onWarning: registry.onWarning,
  );
  ctx.effect(() => registry.registerProvider(provider));
  if (watch) {
    final SkillRootWatcher watcher = SkillRootWatcher(
      roots: provider.roots,
      onInvalidate: registry.invalidate,
      debounce: debounce,
    );
    ctx.effect(watcher.start);
  }
  await registry.refresh();
  return provider;
}

/// 把技能目录挂成一段 system prompt；目录为空时不注册任何段。
SkillCatalogSection provideSkillCatalog(
  Context ctx, {
  int order = kSkillCatalogSectionOrder,
  int descriptionMaxLength = kSkillCatalogDescriptionMaxLength,
}) {
  final SkillCatalogSection section = SkillCatalogSection(
    registry: ctx.require<SkillRegistry>('skillRegistry'),
    prompt: ctx.require<SystemPrompt>('systemPrompt'),
    order: order,
    descriptionMaxLength: descriptionMaxLength,
  );
  ctx.effect(section.attach);
  return section;
}

/// 注册 `skill` 工具。
///
/// [tools] 缺省用 `ctx.tools`；[name] 是注册到工具表的名字，同一张表上挂多个
/// 作用域时需换名。
SkillLoadTool provideSkillTool(
  Context ctx, {
  ToolRegistry? tools,
  String name = kSkillToolName,
}) {
  final SkillLoadTool tool = SkillLoadTool(
    registry: ctx.require<SkillRegistry>('skillRegistry'),
    name: name,
  );
  final ToolRegistry registry = tools ?? ctx.tools;
  ctx.effect(() => registry.register(tool));
  return tool;
}
