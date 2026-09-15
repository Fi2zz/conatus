/// 轮次级取消：打断在飞轮次（barge-in / 退出），让 [AgentLoop.run] 尽快收手。
///
/// Dart 无法强杀在途 Future，故取消是**竞速停止等待**：模型/工具的底层工作
/// 可能仍在后台跑完，但其结果被丢弃，调用方立即可开始新一轮。
library;

import 'dart:async';

/// 取消信号：一次 [AgentLoop.run] 创建一个，传给需要竞速的异步操作。
class AgentCancel {
  bool _cancelled = false;
  final Completer<void> _signal = Completer<void>();

  /// 是否已取消。
  bool get cancelled => _cancelled;

  /// 取消信号 Future：与不可中断的异步操作做 [Future.any] 竞速。
  Future<void> get whenCancelled => _signal.future;

  /// 发出取消信号（幂等）。
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (!_signal.isCompleted) {
      _signal.complete();
    }
  }
}

/// 轮次被取消：由 [AgentLoop.run] 上抛，调用方据此静默收尾（不产回复）。
class AgentCancelled implements Exception {
  const AgentCancelled();

  @override
  String toString() => '轮次已被取消';
}
