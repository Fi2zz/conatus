/// evaluation 的类型词汇：用例与实测结果。
///
/// 报告、基线与判分见 `eval_report.dart`；冻结测试集见 `eval_suite.dart`。
library;

import 'eval_checks.dart';

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
    this.checks = const <EvalCheck>[],
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
        checks: <EvalCheck>[
          for (final Object? item
              in (json['checks'] as List<Object?>?) ?? const <Object?>[])
            if (item is Map)
              EvalCheck.fromJson(Map<String, Object?>.from(item)),
        ],
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

  /// 确定性断言；与上面三个旧字段同时生效。
  final List<EvalCheck> checks;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'input': input,
        if (expectedTools.isNotEmpty) 'expectedTools': expectedTools,
        if (expectedOutput != null) 'expectedOutput': expectedOutput,
        if (maxRounds != null) 'maxRounds': maxRounds,
        if (checks.isNotEmpty)
          'checks': <Map<String, Object?>>[
            for (final EvalCheck check in checks) check.toJson(),
          ],
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
