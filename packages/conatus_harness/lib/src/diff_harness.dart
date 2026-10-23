/// 人可读的 manifest 差异，用于评审与提交信息。
library;

import 'package:conatus_agent/conatus_agent.dart';

import 'manifest.dart';

/// 逐项比较两份 manifest；无差异返回空列表。
///
/// 只比较参与装配的字段；`metadata` 是标注，不进入差异。输出顺序固定：
/// 名字 → 档位 → 预算 → 指令段 → 工具边界。
List<String> diffHarness(HarnessManifest a, HarnessManifest b) {
  final List<String> lines = <String>[];
  _addIfChanged(lines, 'name', a.name, b.name);
  _addIfChanged(lines, 'profile.name', a.profile.name, b.profile.name);
  _addIfChanged(lines, 'profile.reasoningEffort', a.profile.reasoningEffort,
      b.profile.reasoningEffort);
  _diffBudget(lines, a.profile.budget, b.profile.budget);
  _diffSections(lines, a.sections, b.sections);
  _diffTools(lines, a.allowedTools, b.allowedTools);
  _diffForbidden(lines, a.forbiddenTools, b.forbiddenTools);
  return lines;
}

void _diffBudget(
  List<String> lines,
  ToolBudgetPolicy a,
  ToolBudgetPolicy b,
) {
  _addIfChanged(lines, 'budget.economyAfter', a.economyAfter, b.economyAfter);
  _addIfChanged(lines, 'budget.strictAfter', a.strictAfter, b.strictAfter);
  _addIfChanged(
      lines, 'budget.finalizeAfter', a.finalizeAfter, b.finalizeAfter);
  _addIfChanged(lines, 'budget.strictEvery', a.strictEvery, b.strictEvery);
  _diffSet(
      lines, 'budget.finalizeAllowed', a.finalizeAllowed, b.finalizeAllowed);
}

void _diffSections(
  List<String> lines,
  List<PromptSectionSpec> a,
  List<PromptSectionSpec> b,
) {
  final Map<String, String> before = <String, String>{
    for (final PromptSectionSpec section in a) section.name: section.text,
  };
  final Map<String, String> after = <String, String>{
    for (final PromptSectionSpec section in b) section.name: section.text,
  };
  final List<String> added = <String>[
    for (final String name in after.keys)
      if (!before.containsKey(name)) '+$name',
  ];
  final List<String> removed = <String>[
    for (final String name in before.keys)
      if (!after.containsKey(name)) '-$name',
  ];
  added.sort();
  removed.sort();
  final List<String> parts = <String>[...added, ...removed];
  if (parts.isNotEmpty) lines.add('sections: ${parts.join(', ')}');
  for (final String name in before.keys) {
    if (!after.containsKey(name)) continue;
    if (before[name] != after[name]) lines.add('sections.$name: 已修改');
  }
}

void _diffTools(
  List<String> lines,
  Set<String>? a,
  Set<String>? b,
) {
  if (a == null && b == null) return;
  if (a == null) {
    lines.add('allowedTools: null → ${_render(b!)}');
    return;
  }
  if (b == null) {
    lines.add('allowedTools: ${_render(a)} → null');
    return;
  }
  _diffSet(lines, 'allowedTools', a, b);
}

void _diffForbidden(List<String> lines, Set<String> a, Set<String> b) =>
    _diffSet(lines, 'forbiddenTools', a, b);

void _diffSet(
  List<String> lines,
  String label,
  Set<String> a,
  Set<String> b,
) {
  final List<String> added = <String>[
    for (final String item in b)
      if (!a.contains(item)) '+$item',
  ]..sort();
  final List<String> removed = <String>[
    for (final String item in a)
      if (!b.contains(item)) '-$item',
  ]..sort();
  final List<String> parts = <String>[...added, ...removed];
  if (parts.isNotEmpty) lines.add('$label: ${parts.join(', ')}');
}

void _addIfChanged(
  List<String> lines,
  String label,
  Object? a,
  Object? b,
) {
  if (a == b) return;
  lines.add('$label: $a → $b');
}

String _render(Set<String> values) => '[${(_sorted(values)).join(', ')}]';

List<String> _sorted(Set<String> values) => values.toList()..sort();
