import 'dart:convert';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_harness/conatus_harness.dart';
import 'package:test/test.dart';

const ExecutionProfile _profile = ExecutionProfile(
  name: 'standard',
  reasoningEffort: 'medium',
  budget: ToolBudgetPolicy(),
);

HarnessManifest _manifest() => const HarnessManifest(
      name: 'std',
      profile: _profile,
      sections: <PromptSectionSpec>[
        PromptSectionSpec(name: 'guide', text: '先读后写。', order: 5),
        PromptSectionSpec(name: 'verify', text: '结束前复核。'),
      ],
      allowedTools: <String>{'bash', 'read'},
      forbiddenTools: <String>{'rm'},
      metadata: <String, Object?>{'source': 'manual', 'score': 0.8},
    );

Map<String, Object?> _decode(String text) =>
    jsonDecode(text) as Map<String, Object?>;

void main() {
  test('JSON 往返稳定：两次编码字节一致', () {
    final HarnessManifest original = _manifest();
    final String once = jsonEncode(original.toJson());
    final HarnessManifest restored = HarnessManifest.fromJson(_decode(once));
    final String twice = jsonEncode(restored.toJson());

    expect(restored.toJson(), original.toJson());
    expect(twice, once);
  });

  test('集合序列化为排序后的数组', () {
    final Map<String, Object?> json = _manifest().toJson();

    expect(json['allowedTools'], <String>['bash', 'read']);
    expect(json['forbiddenTools'], <String>['rm']);
  });

  test('allowedTools 为 null 时保留 null 语义', () {
    const HarnessManifest open = HarnessManifest(
      name: 'open',
      profile: _profile,
    );

    final HarnessManifest restored =
        HarnessManifest.fromJson(_decode(jsonEncode(open.toJson())));

    expect(open.toJson()['allowedTools'], isNull);
    expect(restored.allowedTools, isNull);
  });

  test('缺省字段用默认值', () {
    final HarnessManifest parsed = HarnessManifest.fromJson(<String, Object?>{
      'name': 'slim',
      'profile': <String, Object?>{
        'name': 'lean',
        'reasoningEffort': 'low',
        'budget': <String, Object?>{
          'economyAfter': 2,
          'strictAfter': 4,
          'finalizeAfter': 8,
          'strictEvery': 2,
          'finalizeAllowed': <String>['read'],
        },
      },
    });

    expect(parsed.sections, isEmpty);
    expect(parsed.forbiddenTools, isEmpty);
    expect(parsed.metadata, isEmpty);
    expect(parsed.allowedTools, isNull);
    expect(parsed.profile.budget.finalizeAfter, 8);
    expect(parsed.profile.budget.finalizeAllowed, <String>{'read'});
  });

  test('缺省 finalizeAllowed 使用 OpenCode 工具名', () {
    final HarnessManifest parsed = HarnessManifest.fromJson(<String, Object?>{
      'name': 'slim',
      'profile': <String, Object?>{'name': 'lean'},
    });

    expect(parsed.profile.budget.finalizeAllowed, <String>{'read'});
  });

  test('profile 往返保留推理强度与全部预算阈值', () {
    final HarnessManifest restored =
        HarnessManifest.fromJson(_decode(jsonEncode(_manifest().toJson())));

    expect(restored.profile.name, 'standard');
    expect(restored.profile.reasoningEffort, 'medium');
    expect(restored.profile.budget.economyAfter, 14);
    expect(restored.profile.budget.strictAfter, 26);
    expect(restored.profile.budget.finalizeAfter, 44);
    expect(restored.profile.budget.strictEvery, 8);
  });
}
