/// 意图路由的变更事件。
library;

import 'intent.dart';
import 'route.dart';

/// 意图事件。
sealed class IntentEvent {
  /// 供子类继承。
  const IntentEvent();
}

/// 注册了一个意图。
class IntentRegistered extends IntentEvent {
  /// 构造事件。
  const IntentRegistered(this.intent);

  /// 被注册的意图。
  final Intent intent;
}

/// 注销了一个意图。
class IntentUnregistered extends IntentEvent {
  /// 构造事件。
  const IntentUnregistered(this.name);

  /// 被注销的意图名。
  final String name;
}

/// 命中了一个意图。
class IntentMatched extends IntentEvent {
  /// 构造事件。
  const IntentMatched(this.result);

  /// 命中结果。
  final RouteResult result;
}

/// 未命中：调用方可以据此走完整 Agent Loop，或交给 `IntentLearner` 积累候选。
class IntentMissed extends IntentEvent {
  /// 构造事件。
  const IntentMissed(this.input);

  /// 原始输入。
  final String input;
}
