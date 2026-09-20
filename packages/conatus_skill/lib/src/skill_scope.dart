/// 技能作用域：父子快照的合并规则与查找辅助。
///
/// 子作用域从父级继承技能，同名由子级赢下；[SkillVisibility] 决定继承哪些。
/// 这里的函数是纯的，注册表只负责在恰当的时机调用它们。
library;

import 'dart:convert';

import 'skill_provider.dart';
import 'skill_types.dart';

/// 作用域可见性判定：返回 `false` 的技能对该作用域不存在。
///
/// 只作用于从父级继承的条目——本注册表自己注册的技能始终可见。
typedef SkillVisibility = bool Function(SkillSummary summary);

/// 合并父级与自身的快照，得到子作用域对外可见的技能集合。
///
/// 父级条目先过 [visible]（`null` 表示全部继承），再与 [own] 按名字合并：
/// 同名由 [own] 赢下，被遮蔽的父级条目经 [onShadowed] 上报。结果按技能名
/// 码位升序。
List<SkillSummary> mergeScopedSummaries({
  required List<SkillSummary> parent,
  required List<SkillSummary> own,
  SkillVisibility? visible,
  void Function(String message)? onShadowed,
}) {
  final Map<String, SkillSummary> merged = <String, SkillSummary>{};
  for (final SkillSummary summary in parent) {
    if (visible != null && !visible(summary)) continue;
    merged[summary.name] = summary;
  }
  for (final SkillSummary summary in own) {
    final SkillSummary? shadowed = merged[summary.name];
    if (shadowed != null) {
      onShadowed?.call(
        '技能 "${summary.name}" 被本作用域覆盖：'
        '${shadowed.source} 的候选被忽略。',
      );
    }
    merged[summary.name] = summary;
  }
  final List<SkillSummary> result = merged.values.toList(growable: false);
  result.sort((SkillSummary a, SkillSummary b) => a.name.compareTo(b.name));
  return result;
}

/// 在摘要列表里按名字查找；未命中返回 `null`。
SkillSummary? findSkillSummary(List<SkillSummary> summaries, String name) {
  for (final SkillSummary summary in summaries) {
    if (summary.name == name) return summary;
  }
  return null;
}

/// 在 provider 列表里按名字查找；未命中返回 `null`。
SkillProvider? providerNamed(List<SkillProvider> providers, String name) {
  for (final SkillProvider provider in providers) {
    if (provider.name == name) return provider;
  }
  return null;
}

/// 两份快照是否逐字段相同：按 [SkillSummary.toJson] 的规范投影比较。
bool sameSkillSnapshot(List<SkillSummary> left, List<SkillSummary> right) =>
    encodeSkillSnapshot(left) == encodeSkillSnapshot(right);

/// 快照的规范 JSON 投影。
String encodeSkillSnapshot(List<SkillSummary> summaries) =>
    jsonEncode(<Map<String, Object?>>[
      for (final SkillSummary summary in summaries) summary.toJson(),
    ]);
