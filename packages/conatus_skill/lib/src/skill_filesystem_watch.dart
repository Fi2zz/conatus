/// 发现根的目录监听：把密集变更合并成一个失效信号。
library;

import 'dart:async';
import 'dart:io';

import 'package:conatus_core/conatus_core.dart';

import 'skill_filesystem_provider.dart';

/// 监听发现根；只监听装配时就已存在的根（缺席的根不会被追认）。
class SkillRootWatcher {
  /// 构造监听器。
  SkillRootWatcher({
    required this.roots,
    required this.onInvalidate,
    this.debounce = const Duration(milliseconds: 250),
  });

  /// 要监听的发现根。
  final List<SkillRoot> roots;

  /// 变更合并后的失效出口。
  final void Function() onInvalidate;

  /// 变更到失效之间的合并窗口。
  final Duration debounce;

  final List<StreamSubscription<FileSystemEvent>> _subscriptions =
      <StreamSubscription<FileSystemEvent>>[];
  Timer? _timer;
  bool _stopped = false;

  /// 对每个已存在的根起监听；返回停止函数（幂等）。
  Disposer start() {
    for (final SkillRoot root in roots) {
      final Directory directory = Directory(root.path);
      if (!directory.existsSync()) continue;
      _subscriptions.add(directory
          .watch(recursive: true)
          .listen(_onEvent, onError: _onWatchError));
    }
    return stop;
  }

  /// 停止监听；已排队的失效信号一并取消。
  void stop() {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    for (final StreamSubscription<FileSystemEvent> subscription
        in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  void _onEvent(FileSystemEvent event) {
    if (_stopped) return;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      if (!_stopped) onInvalidate();
    });
  }

  // 监听失败只是失去自动失效能力，已收集的快照仍然可用，故不向上抛。
  void _onWatchError(Object error, StackTrace stackTrace) {}
}
