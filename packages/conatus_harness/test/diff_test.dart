import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_harness/conatus_harness.dart';
import 'package:test/test.dart';

HarnessManifest _base() => const HarnessManifest(
      name: 'base',
      profile: ExecutionProfile(
        name: 'standard',
        reasoningEffort: 'medium',
        budget: ToolBudgetPolicy(),
      ),
      sections: <PromptSectionSpec>[
        PromptSectionSpec(name: 'guide', text: '先读后写。'),
        PromptSectionSpec(name: 'verify', text: '结束前复核。'),
      ],
      allowedTools: <String>{'read', 'bash'},
      forbiddenTools: <String>{'rm'},
    );

void main() {
  test('完全相同没有差异', () {
    expect(diffHarness(_base(), _base()), isEmpty);
  });

  test('名字与推理强度变化各一行', () {
    const HarnessManifest changed = HarnessManifest(
      name: 'heavy',
      profile: ExecutionProfile(
        name: 'deep',
        reasoningEffort: 'high',
        budget: ToolBudgetPolicy(),
      ),
    );

    final List<String> lines = diffHarness(_base(), changed);

    expect(lines, contains('name: base → heavy'));
    expect(lines, contains('profile.name: standard → deep'));
    expect(lines, contains('profile.reasoningEffort: medium → high'));
  });

  test('预算阈值逐项比较', () {
    const HarnessManifest changed = HarnessManifest(
      name: 'base',
      profile: ExecutionProfile(
        name: 'standard',
        reasoningEffort: 'medium',
        budget: ToolBudgetPolicy(finalizeAfter: 60),
      ),
    );

    expect(diffHarness(_base(), changed),
        contains('budget.finalizeAfter: 44 → 60'));
  });

  test('段增加 / 删除 / 修改', () {
    final HarnessManifest changed = HarnessManifest(
      name: 'base',
      profile: _base().profile,
      sections: const <PromptSectionSpec>[
        PromptSectionSpec(name: 'guide', text: '新规则。'),
        PromptSectionSpec(name: 'extra', text: '新增。'),
      ],
    );

    final List<String> lines = diffHarness(_base(), changed);

    expect(lines, contains('sections: +extra, -verify'));
    expect(lines, contains('sections.guide: 已修改'));
  });

  test('工具白名单从无到有、从有到无', () {
    final HarnessManifest open = HarnessManifest(
      name: 'base',
      profile: _base().profile,
    );

    expect(
      diffHarness(open, _base()),
      contains('allowedTools: null → [bash, read]'),
    );
    expect(
      diffHarness(_base(), open),
      contains('allowedTools: [bash, read] → null'),
    );
  });

  test('禁止名单按增删比较', () {
    final HarnessManifest changed = HarnessManifest(
      name: 'base',
      profile: _base().profile,
      forbiddenTools: const <String>{'rm', 'sudo'},
    );

    expect(diffHarness(_base(), changed), contains('forbiddenTools: +sudo'));
  });

  test('输出顺序稳定：同输入两次结果一致', () {
    const HarnessManifest changed = HarnessManifest(
      name: 'other',
      profile: ExecutionProfile(
        name: 'lean',
        reasoningEffort: 'low',
        budget: ToolBudgetPolicy(economyAfter: 2),
      ),
      forbiddenTools: <String>{'a', 'b'},
    );

    expect(diffHarness(_base(), changed), diffHarness(_base(), changed));
  });
}
