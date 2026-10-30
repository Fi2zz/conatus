/// 检查点动作的串行链：同一时刻只跑一个，单次失败不毒化后续。
///
/// 差量必须落在基线之后（否则基线还在写，差量已按「基线缺失」分类，合成
/// 出从未存在过的混合状态），故 [run] 把所有动作排成一条链。动作抛出的异常
/// 只交给它自己的 Future：链尾永远正常完成，否则一次失败会让后续动作永久
/// 挂在 `then` 上（`flush` 也就永远等不到）。
library;

import 'dart:async';

/// 串行执行器。
class CheckpointChain {
  Future<void> _tail = Future<void>.value();

  /// 当前链尾：`await` 它等于等所有已入队动作完成。
  Future<void> get settled => _tail;

  /// 把 [action] 排到链尾，返回它的结果（异常原样透传给调用方）。
  Future<T> run<T>(Future<T> Function() action) {
    final Completer<T> completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }
}
