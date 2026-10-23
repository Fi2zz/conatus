/// 冻结测试集：用例集合 + 内容 hash，防止候选之间测试漂移。
library;

import 'dart:convert';

import 'eval_types.dart';

/// 一套固定的评估用例；[hash] 由用例内容决定，与顺序无关。
class EvalSuite {
  EvalSuite(List<EvalCase> cases)
      : cases = List<EvalCase>.unmodifiable(cases),
        hash = hashEvalCases(cases);

  /// 从 JSON 还原；记录的 hash 与内容不符时抛 [FormatException]。
  factory EvalSuite.fromJson(Map<String, Object?> json) {
    final List<EvalCase> parsed = <EvalCase>[
      for (final Object? item
          in (json['cases'] as List<Object?>?) ?? const <Object?>[])
        if (item is Map) EvalCase.fromJson(Map<String, Object?>.from(item)),
    ];
    final EvalSuite suite = EvalSuite(parsed);
    final String? recorded = json['hash'] as String?;
    if (recorded != null && recorded != suite.hash) {
      throw FormatException('测试集 hash 不匹配：记录 $recorded，实际 ${suite.hash}');
    }
    return suite;
  }

  /// 用例（按传入顺序）。
  final List<EvalCase> cases;

  /// 内容 hash。
  final String hash;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'hash': hash,
        'cases': <Map<String, Object?>>[
          for (final EvalCase evalCase in cases) evalCase.toJson(),
        ],
      };
}

/// 计算用例集 hash：按 id 排序后取规范 JSON，再算 32 位 FNV-1a。
///
/// 顺序不影响结果；任何字段变化都会改变 hash。
String hashEvalCases(List<EvalCase> cases) {
  final List<EvalCase> sorted = List<EvalCase>.of(cases)
    ..sort((EvalCase a, EvalCase b) => a.id.compareTo(b.id));
  final String canonical = jsonEncode(<Map<String, Object?>>[
    for (final EvalCase evalCase in sorted) evalCase.toJson(),
  ]);
  int hash = 0x811c9dc5;
  for (final int byte in utf8.encode(canonical)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
