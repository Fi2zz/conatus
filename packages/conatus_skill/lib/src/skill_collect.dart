/// 技能收集：并发前串行地问每个 provider 要候选，排完序收敛成摘要列表。
library;

import 'skill_provider.dart';
import 'skill_ranking.dart';
import 'skill_types.dart';

/// 问每个 provider 要一轮候选，并按层内优先级收敛成摘要列表。
///
/// 单个 provider 抛错只影响它自己：错误经 [onWarning] 上报，其余 provider 的
/// 产出照常生效。运行时技能以 [kSkillRuntimeRank] 参与同一轮排序。
Future<List<SkillSummary>> collectSkillSummaries({
  required List<SkillProvider> providers,
  required Iterable<SkillRegistration> runtime,
  void Function(String message)? onWarning,
}) async {
  final List<SkillCandidateBatch> batches = <SkillCandidateBatch>[];
  if (runtime.isNotEmpty) {
    batches.add(SkillCandidateBatch(
      providerOrder: -1,
      candidates: <SkillCandidate>[
        for (final SkillRegistration registration in runtime)
          SkillCandidate(
            summary: registration.toSummary(),
            rank: kSkillRuntimeRank,
          ),
      ],
    ));
  }
  int order = 0;
  for (final SkillProvider provider in providers) {
    batches.add(SkillCandidateBatch(
      providerOrder: order,
      candidates: await _listSafely(provider, onWarning),
    ));
    order++;
  }
  final List<SkillCandidate> ranked =
      rankSkillCandidates(batches, onShadowed: onWarning);
  return <SkillSummary>[
    for (final SkillCandidate candidate in ranked) candidate.summary,
  ];
}

Future<List<SkillCandidate>> _listSafely(
  SkillProvider provider,
  void Function(String message)? onWarning,
) async {
  try {
    return await provider.list();
  } on Object catch (error) {
    onWarning?.call('技能 provider "${provider.name}" 列举失败：$error');
    return const <SkillCandidate>[];
  }
}
