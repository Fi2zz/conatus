/// 意图的确定性排序：priority 降序，同 priority 保注册顺序。
library;

import '../intent.dart';

/// 按 [Intent.priority] 降序排列；同 priority 保持 [intents] 的原有顺序。
///
/// `List.sort` 在 Dart 里**不稳定**，所以显式带原始下标做 tiebreaker——否则
/// 「同优先级按注册顺序」这条不变式会随实现细节漂移。
List<Intent> orderByPriority(List<Intent> intents) {
  final List<int> order = <int>[
    for (int i = 0; i < intents.length; i++) i,
  ];
  order.sort((int a, int b) {
    final int byPriority = intents[b].priority.compareTo(intents[a].priority);
    return byPriority != 0 ? byPriority : a.compareTo(b);
  });
  return <Intent>[for (final int index in order) intents[index]];
}
