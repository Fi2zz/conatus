/// Backbone 配置与 backbone-conditional 配对评估结果类型。
library;

/// Backbone 配置：评估在哪个模型配置下进行。
class BackboneConfig {
  const BackboneConfig({
    required this.provider,
    required this.model,
    this.decodingSettings,
    this.interactionBudget,
  });

  final String provider;
  final String model;
  final Map<String, Object?>? decodingSettings;
  final int? interactionBudget;

  String get label => '$provider/$model';

  Map<String, Object?> toJson() => <String, Object?>{
        'provider': provider,
        'model': model,
        'decodingSettings': decodingSettings,
        'interactionBudget': interactionBudget,
      };
}

/// Backbone-conditional 评估结果。
class ConditionalEvalResult {
  const ConditionalEvalResult({
    required this.backbone,
    required this.baselineScore,
    required this.candidateScore,
    required this.improvement,
    required this.passed,
  });

  final BackboneConfig backbone;
  final double baselineScore;
  final double candidateScore;
  final double improvement;
  final bool passed;
}
