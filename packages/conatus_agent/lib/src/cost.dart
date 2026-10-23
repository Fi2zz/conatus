/// 成本口径：用量归一、费率折算与累计。
///
/// 本层只做纯计算：费率由调用方注入（框架不内置价目表），用量键名同时兼容
/// Chat Completions（`prompt_tokens`）与 Responses（`input_tokens`）。费率缺失时
/// 成本返回 `null` 而不是 0——一个错的金额比没有金额更糟。
library;

/// 一次调用或一段累计的 token 用量。
class TokenUsage {
  const TokenUsage({
    this.prompt = 0,
    this.cachedPrompt = 0,
    this.completion = 0,
  });

  /// 从 provider 返回的原始 `usage` 归一；空表或类型不符按 0 计。
  factory TokenUsage.parse(Map<String, dynamic> usage) => TokenUsage(
        prompt: _intOf(usage, 'prompt_tokens') + _intOf(usage, 'input_tokens'),
        cachedPrompt: _intOf(
                _tableOf(usage, 'prompt_tokens_details'), 'cached_tokens') +
            _intOf(_tableOf(usage, 'input_tokens_details'), 'cached_tokens'),
        completion:
            _intOf(usage, 'completion_tokens') + _intOf(usage, 'output_tokens'),
      );

  /// 零用量。
  static const TokenUsage zero = TokenUsage();

  /// 输入 token（含缓存命中部分）。
  final int prompt;

  /// 其中命中缓存、按折扣价计费的部分。
  final int cachedPrompt;

  /// 输出 token。
  final int completion;

  /// 是否真的拿到了数字（区别于接口返回 0）。
  bool get known => prompt > 0 || completion > 0;

  /// 未命中缓存的输入部分。
  int get freshPrompt => (prompt - cachedPrompt).clamp(0, prompt);

  /// 两个用量逐维相加。
  TokenUsage operator +(TokenUsage other) => TokenUsage(
        prompt: prompt + other.prompt,
        cachedPrompt: cachedPrompt + other.cachedPrompt,
        completion: completion + other.completion,
      );

  static Map<String, dynamic>? _tableOf(
    Map<String, dynamic> usage,
    String key,
  ) {
    final Object? value = usage[key];
    return value is Map<String, dynamic> ? value : null;
  }

  static int _intOf(Map<String, dynamic>? table, String key) {
    final Object? value = table?[key];
    return value is num ? value.toInt() : 0;
  }
}

/// 模型单价（美元 / 百万 token）。
class ModelRate {
  const ModelRate({
    required this.inputPerMillion,
    required this.cachedPerMillion,
    required this.outputPerMillion,
  });

  /// 未缓存输入单价。
  final double inputPerMillion;

  /// 缓存命中输入单价。
  final double cachedPerMillion;

  /// 输出单价。
  final double outputPerMillion;

  /// 折算成本：未缓存输入、缓存输入、输出三段分价。
  double costOf(TokenUsage usage) =>
      usage.freshPrompt / 1e6 * inputPerMillion +
      usage.cachedPrompt / 1e6 * cachedPerMillion +
      usage.completion / 1e6 * outputPerMillion;
}

/// 按固定费率累计用量与成本。
///
/// 用量未知的调用直接忽略（不计 [calls]）；费率缺失时照常累计 token 与调用数，
/// 但 [cost] 为 `null`，并单独记入 [unknownRateCalls]。
class CostAccumulator {
  CostAccumulator({this.rate});

  /// 费率；`null` 表示未知，成本不可得。
  final ModelRate? rate;

  TokenUsage _tokens = TokenUsage.zero;
  int _calls = 0;
  int _unknownRateCalls = 0;

  /// 已计入的调用数。
  int get calls => _calls;

  /// 累计用量。
  TokenUsage get tokens => _tokens;

  /// 费率缺失却产生了用量的调用数。
  int get unknownRateCalls => _unknownRateCalls;

  /// 累计成本；无调用或费率缺失时为 `null`。
  double? get cost {
    final ModelRate? current = rate;
    if (current == null || _calls == 0) return null;
    return current.costOf(_tokens);
  }

  /// 记录一次原始 `usage`。
  void add(Map<String, dynamic> usage) => addTokens(TokenUsage.parse(usage));

  /// 记录一次已归一的用量。
  void addTokens(TokenUsage usage) {
    if (!usage.known) return;
    _tokens = _tokens + usage;
    _calls++;
    if (rate == null) _unknownRateCalls++;
  }

  /// 每次成功任务的成本；没有成功任务或成本不可得时为 `null`。
  double? costOfPass(int passedTasks) {
    final double? total = cost;
    if (total == null || passedTasks <= 0) return null;
    return total / passedTasks;
  }
}
