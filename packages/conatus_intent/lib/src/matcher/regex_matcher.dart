/// 正则匹配：确定性最高、零延迟，永远先跑。
library;

import '../intent.dart';
import '../route.dart';
import 'priority.dart';

/// 正则匹配器。
class RegexMatcher {
  /// 构造匹配器。
  const RegexMatcher();

  /// 在 [intents] 中找正则命中；未命中返回 null。
  RouteResult? match(String input, List<Intent> intents) {
    for (final Intent intent in orderByPriority(intents)) {
      for (final Pattern pattern in intent.patterns) {
        if (pattern.allMatches(input).isNotEmpty) {
          return RouteResult(
            intent: intent,
            confidence: 1.0,
            source: RouteSource.regex,
            input: input,
          );
        }
      }
    }
    return null;
  }
}
