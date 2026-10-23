/// 评估报告、基线与默认判分。
library;

import 'eval_checks.dart';
import 'eval_types.dart';

/// 一次评估的报告。
class EvalReport {
  const EvalReport(this.results, {this.suiteHash});

  /// 从 JSON 反序列化。
  factory EvalReport.fromJson(Map<String, Object?> json) => EvalReport(
        <EvalResult>[
          for (final Object? item
              in (json['results'] as List<Object?>?) ?? const <Object?>[])
            if (item is Map)
              EvalResult.fromJson(Map<String, Object?>.from(item)),
        ],
        suiteHash: json['suiteHash'] as String?,
      );

  /// 各用例结果。
  final List<EvalResult> results;

  /// 产出这份报告时所用测试集的 hash；没有记录时为 `null`。
  final String? suiteHash;

  /// 通过数。
  int get passedCount => results.where((EvalResult r) => r.passed).length;

  /// 通过率（无用例时为 0）。
  double get passRate => results.isEmpty ? 0 : passedCount / results.length;

  /// 平均步数（无用例时为 0）。
  double get averageRounds => results.isEmpty
      ? 0
      : results.fold<int>(0, (int sum, EvalResult r) => sum + r.rounds) /
          results.length;

  /// 与基线对比。两侧都有 hash 且不同时抛 [StateError]。
  EvalDiff compareTo(EvalReport baseline) {
    final String? mine = suiteHash;
    final String? theirs = baseline.suiteHash;
    if (mine != null && theirs != null && mine != theirs) {
      throw StateError('测试集不同（$mine vs $theirs），不能直接比较');
    }
    return EvalDiff(
      passRateDelta: passRate - baseline.passRate,
      averageRoundsDelta: averageRounds - baseline.averageRounds,
    );
  }

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'results': <Map<String, Object?>>[
          for (final EvalResult r in results) r.toJson(),
        ],
        if (suiteHash != null) 'suiteHash': suiteHash,
      };
}

/// 报告与基线的差异。
class EvalDiff {
  const EvalDiff({
    required this.passRateDelta,
    required this.averageRoundsDelta,
  });

  /// 通过率差。
  final double passRateDelta;

  /// 平均步数差。
  final double averageRoundsDelta;

  @override
  String toString() => '通过率 ${_signed(passRateDelta * 100)}%，'
      '平均步数 ${_signed(averageRoundsDelta)}';

  static String _signed(double value) =>
      value >= 0 ? '+${value.toStringAsFixed(1)}' : value.toStringAsFixed(1);
}

/// 默认判分：旧字段（工具子集 / 关键词 / 步数）与 [EvalCase.checks] 全部满足。
bool defaultEvalJudge(EvalCase evalCase, EvalResult result) {
  final bool toolsOk =
      evalCase.expectedTools.every(result.actualTools.contains);
  final bool outputOk = evalCase.expectedOutput == null ||
      result.actualOutput.contains(evalCase.expectedOutput!);
  final bool roundsOk =
      evalCase.maxRounds == null || result.rounds <= evalCase.maxRounds!;
  final bool checksOk =
      evalCase.checks.every((EvalCheck check) => check.evaluate(result));
  return toolsOk && outputOk && roundsOk && checksOk;
}
