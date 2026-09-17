/// Maker-Checker 协作模式：Maker 提案，Checker 审查，循环直到满意。
///
/// 适用场景：质量把关（写代码 → 审查；写文档 → 校对）。Maker 每轮
/// 根据上轮 Checker 反馈修订提案；Checker 审查后给出 verdict。verdict
/// 含「approve / approved / 通过 / 满意」视为通过，否则把反馈回传 Maker。
/// 达到 [maxIterations] 返回最后一版提案。
///
/// [options]['maker'] / ['checker'] 指定成员名；['maxIterations'] 控制
/// 最大迭代次数（默认 5）。返回最终提案。
library;

import 'dart:async';

import '../agent_team.dart';
import '../team_pattern.dart';
import '../teammate.dart';

/// Maker-Checker 模式：提案 → 审查 → 修订循环。
class MakerCheckerPattern implements TeamPattern {
  const MakerCheckerPattern({this.defaultMaxIterations = 5});

  /// 缺省最大迭代次数。
  final int defaultMaxIterations;

  @override
  String get name => 'maker_checker';

  @override
  Future<Object?> execute({
    required AgentTeam team,
    required String input,
    Map<String, Object?> options = const <String, Object?>{},
  }) async {
    final String makerName = '${options['maker'] ?? 'maker'}';
    final String checkerName = '${options['checker'] ?? 'checker'}';
    final int maxIter = _asInt(options['maxIterations'], defaultMaxIterations);
    final Teammate maker = await team.spawn(name: makerName);
    final Teammate checker = await team.spawn(name: checkerName);
    String feedback = input;
    String proposal = '';
    for (int i = 0; i < maxIter; i++) {
      proposal = await team.ask(maker.id, i == 0 ? input : '根据反馈修订：$feedback');
      final String verdict = await team.ask(checker.id, '审查这个提案：$proposal');
      if (_approved(verdict)) return proposal;
      feedback = verdict;
    }
    return proposal;
  }

  /// 通过判定：先排除否定表述，再看肯定关键词。
  ///
  /// 否定必须先判——「不通过」是「通过」的超串，只做肯定匹配会把驳回
  /// 误判为放行。
  bool _approved(String verdict) {
    final String lower = verdict.toLowerCase();
    if (lower.contains('reject') ||
        lower.contains('not approve') ||
        verdict.contains('不通过') ||
        verdict.contains('未通过') ||
        verdict.contains('不满意') ||
        verdict.contains('不认可') ||
        verdict.contains('驳回')) {
      return false;
    }
    return lower.contains('approve') ||
        verdict.contains('通过') ||
        verdict.contains('满意') ||
        verdict.contains('认可');
  }

  int _asInt(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw) ?? fallback;
    return fallback;
  }
}
