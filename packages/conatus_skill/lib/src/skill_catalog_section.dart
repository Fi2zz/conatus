/// 目录段与 system prompt 之间的挂载控制器：空目录不注册任何段。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'skill_catalog.dart';
import 'skill_registry.dart';
import 'skill_types.dart';

/// 目录段在 system prompt 里的名字。
const String kSkillCatalogSectionName = 'skills';

/// 目录段在 system prompt 里的默认排序权重。
const int kSkillCatalogSectionOrder = 50;

/// 跟随注册表，把可用技能目录挂成一段 system prompt。
///
/// 目录为空时撤销该段——没有技能时 prompt 与本插件不存在时逐字相同。
class SkillCatalogSection {
  /// 构造控制器。
  SkillCatalogSection({
    required this.registry,
    required this.prompt,
    this.order = kSkillCatalogSectionOrder,
    this.descriptionMaxLength = kSkillCatalogDescriptionMaxLength,
  });

  /// 技能来源。
  final SkillRegistry registry;

  /// 目标 system prompt。
  final SystemPrompt prompt;

  /// 段的排序权重。
  final int order;

  /// 目录里单条描述的长度上限。
  final int descriptionMaxLength;

  Disposer? _section;
  String _name = kSkillCatalogSectionName;

  /// 开始跟随注册表；返回撤销函数（幂等）。
  ///
  /// [name] 是挂到 prompt 上的段名：同一份 [prompt] 上挂多个作用域的目录段时，
  /// 各作用域要用不同的段名。缺省 [kSkillCatalogSectionName]。
  Disposer attach({String name = kSkillCatalogSectionName}) {
    _name = name;
    final Disposer listener = registry.onChange(sync);
    sync();
    return () {
      listener();
      _detachSection();
    };
  }

  /// 按当前快照挂上或摘掉目录段。
  void sync() {
    if (registry.modelInvocable.isEmpty) {
      _detachSection();
      return;
    }
    _section ??= prompt.section(PromptSection(
      name: _name,
      order: order,
      text: _renderCurrent,
    ));
  }

  String _renderCurrent() {
    final List<SkillSummary> skills = registry.modelInvocable;
    if (skills.isEmpty) return '';
    return renderSkillCatalog(skills,
        descriptionMaxLength: descriptionMaxLength);
  }

  void _detachSection() {
    final Disposer? section = _section;
    _section = null;
    section?.call();
  }
}
