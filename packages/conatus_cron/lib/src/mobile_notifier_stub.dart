/// 非 Flutter 环境下的移动通知端口构建：返回 null。
///
/// 被 `cron_notify.dart` 以条件导出引用，仅在 `dart.library.ui` 不存在时编译
/// （纯 Dart / CLI 宿主）；Flutter 环境改由 `mobile_notifier_flutter.dart` 提供
/// 基于 MethodChannel 的实现。
library;

import 'cron_notify.dart' show CronNotifier;

/// 返回 null：纯 Dart 环境没有 MethodChannel，移动端通知由宿主自行注入
/// [CronNotifier]，或改用 Flutter 构建（`mobileCronNotifier` 自动切换实现）。
CronNotifier? buildMobileCronNotifier(String channel) => null;
