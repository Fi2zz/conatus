# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

初始实现——会话本地持久提醒，从 `conatus` 之外的功能需求引入为独立包：

- `SessionSchedule` / `provideSessionSchedule`（服务键 `'schedule'`）：提醒写在会话
  事件流的 `schedule/change` 事件里（严格版本 1 解码），`provideScheduleTools` 注册
  `schedule_create` / `schedule_list` / `schedule_delete` 三个工具
- `ScheduleRuntime` / `provideScheduleRuntime`（服务键 `'scheduleRuntime'`）：分段
  定时器唤醒、墙钟重采样、固定 framing；只在投递入队成功后写入派发记录
- `at` 同时支持显式偏移的 RFC 3339 串与 `{date, time, time_zone}` 本地对象
  （依赖 `timezone` 的 IANA 时区库，夏令时缺口拒绝、重叠取较早）
