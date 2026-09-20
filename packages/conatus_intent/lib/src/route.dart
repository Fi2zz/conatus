/// 路由结果的词汇：来源、结果与上下文。
library;

import 'intent.dart';

/// 路由来源。
enum RouteSource {
  /// 正则匹配。
  regex,

  /// 向量匹配。
  vector,

  /// 未命中。
  none,
}

/// 路由结果。
class RouteResult {
  /// 构造结果。
  const RouteResult({
    required this.intent,
    required this.confidence,
    required this.source,
    this.input,
  });

  /// 未命中的结果。
  factory RouteResult.missed(String input) => RouteResult(
        intent: null,
        confidence: 0.0,
        source: RouteSource.none,
        input: input,
      );

  /// 命中的意图；未命中时为 null。
  final Intent? intent;

  /// 置信度。正则命中为 1.0，向量命中为相似度。
  final double confidence;

  /// 路由来源。
  final RouteSource source;

  /// 原始输入。
  final String? input;

  /// 是否命中。
  bool get matched => intent != null;
}

/// 路由上下文。
///
/// 动作执行时可见的输入与附加状态（设备状态、用户偏好等）。
class RouteContext {
  /// 构造上下文。
  const RouteContext({
    required this.input,
    this.state = const <String, Object?>{},
  });

  /// 原始输入。
  final String input;

  /// 附加状态。设备状态、用户偏好等。
  final Map<String, Object?> state;

  /// 状态里的值。
  T? get<T>(String key) => state[key] as T?;
}
