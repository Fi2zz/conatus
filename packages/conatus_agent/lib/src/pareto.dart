/// 三档选型：帕累托过滤 + 归一化加权平方距离。
///
/// 只吃 `(通过率, 平均成本)` 两个数，不依赖评估器实现；对应 HarnessPro 的
/// lite / medium / heavy 三个部署预算档。权重与论文一致：
/// lite `(1, 2)`、medium `(1, 1)`、heavy `(2, 1)`。
library;

/// 一个待选候选（一次 harness / 配置 / 提示词版本）。
class SelectionCandidate {
  const SelectionCandidate({
    required this.id,
    required this.passRate,
    required this.meanCost,
  });

  /// 候选标识。
  final String id;

  /// 通过率（0.0–1.0）。
  final double passRate;

  /// 单任务平均成本；单位由调用方决定（美元 / token）。
  final double meanCost;

  @override
  String toString() => 'SelectionCandidate($id, $passRate, $meanCost)';
}

/// 部署预算档。
enum SelectionMode {
  /// 成本优先。
  lite,

  /// 性能与成本并重。
  medium,

  /// 性能优先。
  heavy,
}

/// 过滤出帕累托前沿（被支配者剔除，保持输入顺序）。
///
/// 支配定义：两项都不差，且至少一项更好。完全相同不算支配。
List<SelectionCandidate> paretoFrontier(
  Iterable<SelectionCandidate> candidates,
) {
  final List<SelectionCandidate> all = List<SelectionCandidate>.of(candidates);
  return <SelectionCandidate>[
    for (final SelectionCandidate candidate in all)
      if (!all.any((SelectionCandidate other) =>
          !identical(other, candidate) && _dominates(other, candidate)))
        candidate,
  ];
}

/// 在前沿里为 [mode] 选一个代表；空集返回 `null`。
///
/// 平手时返回输入顺序里最先出现的那个。
SelectionCandidate? selectRepresentative(
  List<SelectionCandidate> frontier,
  SelectionMode mode,
) {
  if (frontier.isEmpty) return null;
  final double minPass = frontier
      .map((SelectionCandidate c) => c.passRate)
      .reduce((double a, double b) => a < b ? a : b);
  final double maxPass = frontier
      .map((SelectionCandidate c) => c.passRate)
      .reduce((double a, double b) => a > b ? a : b);
  final double minCost = frontier
      .map((SelectionCandidate c) => c.meanCost)
      .reduce((double a, double b) => a < b ? a : b);
  final double maxCost = frontier
      .map((SelectionCandidate c) => c.meanCost)
      .reduce((double a, double b) => a > b ? a : b);
  final (double, double) weights = _weightsOf(mode);

  SelectionCandidate? best;
  double bestScore = double.infinity;
  for (final SelectionCandidate candidate in frontier) {
    final double score = weights.$1 *
            _squared(_normalize(
              maxPass - candidate.passRate,
              maxPass - minPass,
            )) +
        weights.$2 *
            _squared(
                _normalize(candidate.meanCost - minCost, maxCost - minCost));
    if (score < bestScore) {
      bestScore = score;
      best = candidate;
    }
  }
  return best;
}

/// 一次为三档各选一个代表；空集返回空表。
Map<SelectionMode, SelectionCandidate> selectRepresentatives(
  Iterable<SelectionCandidate> candidates,
) {
  final List<SelectionCandidate> frontier = paretoFrontier(candidates);
  final Map<SelectionMode, SelectionCandidate> picked =
      <SelectionMode, SelectionCandidate>{};
  for (final SelectionMode mode in SelectionMode.values) {
    final SelectionCandidate? candidate = selectRepresentative(frontier, mode);
    if (candidate != null) picked[mode] = candidate;
  }
  return picked;
}

bool _dominates(SelectionCandidate a, SelectionCandidate b) {
  final bool noWorse = a.passRate >= b.passRate && a.meanCost <= b.meanCost;
  final bool strictlyBetter =
      a.passRate > b.passRate || a.meanCost < b.meanCost;
  return noWorse && strictlyBetter;
}

/// 极值相等时该维度偏差记 0，避免除零与 NaN。
double _normalize(double value, double range) => range <= 0 ? 0 : value / range;

double _squared(double value) => value * value;

(double, double) _weightsOf(SelectionMode mode) => switch (mode) {
      SelectionMode.lite => (1, 2),
      SelectionMode.medium => (1, 1),
      SelectionMode.heavy => (2, 1),
    };
