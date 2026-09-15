/// evaluation 的类型词汇：用例、结果、报告与默认判分。
library;

/// 判分函数：给定 case 与实测结果，返回是否通过。
typedef EvalJudge = bool Function(EvalCase evalCase, EvalResult result);

/// 一条评估用例。
class EvalCase {
  const EvalCase({
    required this.id,
    required this.input,
    this.expectedTools = const <String>[],
    this.expectedOutput,
    this.maxRounds,
  });

  /// 从 JSON 反序列化。
  factory EvalCase.fromJson(Map<String, Object?> json) => EvalCase(
        id: '${json['id'] ?? ''}',
        input: '${json['input'] ?? ''}',
        expectedTools: <String>[
          for (final Object? item
              in (json['expectedTools'] as List<Object?>?) ?? const <Object?>[])
            '$item',
        ],
        expectedOutput: json['expectedOutput'] as String?,
        maxRounds: json['maxRounds'] as int?,
      );

  /// 用例 id。
  final String id;

  /// 用户输入。
  final String input;

  /// 期望调用的工具（须为实际调用集合的子集）。
  final List<String> expectedTools;

  /// 期望输出包含的关键词。
  final String? expectedOutput;

  /// 最大步数限制。
  final int? maxRounds;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'input': input,
        if (expectedTools.isNotEmpty) 'expectedTools': expectedTools,
        if (expectedOutput != null) 'expectedOutput': expectedOutput,
        if (maxRounds != null) 'maxRounds': maxRounds,
      };
}

/// 一条 case 的实测结果。
class EvalResult {
  const EvalResult({
    required this.caseId,
    required this.passed,
    required this.actualTools,
    required this.actualOutput,
    required this.rounds,
    required this.duration,
  });

  /// 从 JSON 反序列化。
  factory EvalResult.fromJson(Map<String, Object?> json) => EvalResult(
        caseId: '${json['caseId'] ?? ''}',
        passed: json['passed'] == true,
        actualTools: <String>[
          for (final Object? item
              in (json['actualTools'] as List<Object?>?) ?? const <Object?>[])
            '$item',
        ],
        actualOutput: '${json['actualOutput'] ?? ''}',
        rounds: json['rounds'] as int? ?? 0,
        duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      );

  /// 用例 id。
  final String caseId;

  /// 是否通过。
  final bool passed;

  /// 实际调用的工具（按序）。
  final List<String> actualTools;

  /// 实际输出。
  final String actualOutput;

  /// 工具步数。
  final int rounds;

  /// 耗时。
  final Duration duration;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'caseId': caseId,
        'passed': passed,
        'actualTools': actualTools,
        'actualOutput': actualOutput,
        'rounds': rounds,
        'durationMs': duration.inMilliseconds,
      };
}

/// 一次评估的报告。
class EvalReport {
  const EvalReport(this.results);

  /// 从 JSON 反序列化。
  factory EvalReport.fromJson(Map<String, Object?> json) =>
      EvalReport(<EvalResult>[
        for (final Object? item
            in (json['results'] as List<Object?>?) ?? const <Object?>[])
          if (item is Map) EvalResult.fromJson(Map<String, Object?>.from(item)),
      ]);

  /// 各用例结果。
  final List<EvalResult> results;

  /// 通过数。
  int get passedCount => results.where((EvalResult r) => r.passed).length;

  /// 通过率（无用例时为 0）。
  double get passRate => results.isEmpty ? 0 : passedCount / results.length;

  /// 平均步数（无用例时为 0）。
  double get averageRounds => results.isEmpty
      ? 0
      : results.fold<int>(0, (int sum, EvalResult r) => sum + r.rounds) /
          results.length;

  /// 与基线对比。
  EvalDiff compareTo(EvalReport baseline) => EvalDiff(
        passRateDelta: passRate - baseline.passRate,
        averageRoundsDelta: averageRounds - baseline.averageRounds,
      );

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'results': <Map<String, Object?>>[
          for (final EvalResult r in results) r.toJson(),
        ],
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

/// 默认判分：期望工具为实际工具子集、输出含关键词、步数不超限。
bool defaultEvalJudge(EvalCase evalCase, EvalResult result) {
  final bool toolsOk =
      evalCase.expectedTools.every(result.actualTools.contains);
  final bool outputOk = evalCase.expectedOutput == null ||
      result.actualOutput.contains(evalCase.expectedOutput!);
  final bool roundsOk =
      evalCase.maxRounds == null || result.rounds <= evalCase.maxRounds!;
  return toolsOk && outputOk && roundsOk;
}
