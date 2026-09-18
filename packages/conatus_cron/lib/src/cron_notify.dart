/// 系统通知端口：任务运行结束时的原生 OS 通知。
///
/// conatus_cron 只定义抽象端口，不做具体平台实现；投递方式由宿主（具体调用方）
/// 注入 [CronNotifier] 决定。桌面实现见 conatus_tui（macOS `osascript` /
/// Linux `notify-send`），移动端宿主可注入 flutter_local_notifications 等实现。
///
/// 通知是 best-effort：由实现保证不抛错、不阻塞调度器。
library;

/// 系统通知端口：收到标题与正文，投递方式由实现决定。
typedef CronNotifier = void Function(String title, String body);
