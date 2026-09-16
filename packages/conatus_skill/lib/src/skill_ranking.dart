/// 层内排序与同名遮蔽：把多个 provider 的产出收敛成一份候选列表。
library;

import 'skill_types.dart';

/// 一个 provider 在某一轮收集里的产出。
class SkillCandidateBatch {
  /// 构造批次。
  const SkillCandidateBatch({
    required this.providerOrder,
    required this.candidates,
  });

  /// provider 的注册顺序（运行时技能为 `-1`）。
  final int providerOrder;

  /// 该 provider 产出的候选（provider 内的产出顺序）。
  final List<SkillCandidate> candidates;
}

/// 按「rank → provider 注册顺序 → provider 内产出顺序」排序，同名只留第一个；
/// 被遮蔽的候选通过 [onShadowed] 上报。结果按技能名码位升序。
List<SkillCandidate> rankSkillCandidates(
  Iterable<SkillCandidateBatch> batches, {
  void Function(String message)? onShadowed,
}) {
  final List<_RankedCandidate> ranked = <_RankedCandidate>[];
  int localOrder = 0;
  for (final SkillCandidateBatch batch in batches) {
    for (final SkillCandidate candidate in batch.candidates) {
      ranked.add(_RankedCandidate(candidate, batch.providerOrder, localOrder));
      localOrder++;
    }
  }
  ranked.sort(_byPrecedence);

  final Map<String, _RankedCandidate> winners = <String, _RankedCandidate>{};
  for (final _RankedCandidate entry in ranked) {
    final String name = entry.candidate.summary.name;
    final _RankedCandidate? winner = winners[name];
    if (winner == null) {
      winners[name] = entry;
      continue;
    }
    onShadowed?.call(
      '技能 "$name" 被 ${winner.candidate.summary.provider} 遮蔽：'
      '${entry.candidate.summary.source} 的候选被忽略。',
    );
  }

  final List<SkillCandidate> result = <SkillCandidate>[
    for (final _RankedCandidate entry in winners.values) entry.candidate,
  ];
  result.sort((SkillCandidate a, SkillCandidate b) =>
      a.summary.name.compareTo(b.summary.name));
  return result;
}

int _byPrecedence(_RankedCandidate a, _RankedCandidate b) {
  final int byRank = a.candidate.rank.compareTo(b.candidate.rank);
  if (byRank != 0) return byRank;
  final int byProvider = a.providerOrder.compareTo(b.providerOrder);
  return byProvider != 0 ? byProvider : a.localOrder.compareTo(b.localOrder);
}

class _RankedCandidate {
  const _RankedCandidate(this.candidate, this.providerOrder, this.localOrder);

  final SkillCandidate candidate;
  final int providerOrder;
  final int localOrder;
}
