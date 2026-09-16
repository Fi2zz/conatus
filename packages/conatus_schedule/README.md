# conatus_schedule

conatus 的会话本地持久提醒（仅依赖 `conatus_core`、`conatus_foundation` 与
`timezone` 的 IANA 时区库）。

模型用 `schedule_create` / `schedule_list` / `schedule_delete` 三个工具管理当前
会话的提醒；提醒在延迟后、绝对时间或固定间隔触发，到期时作为一条普通消息回到
**同一会话**——没有邮件、短信或推送，冷会话只会在恢复后处理逾期记录。

## 状态权威

提醒没有独立存储。唯一权威是会话事件流里的 `schedule/change` 事件（协议版本 1）：

- **严格解码**——未知版本、未知操作、额外字段、非法标识、非规范时刻、形状不符的
  dispatch 一律失败，损坏的流会大声报错，而不是派生出一个看起来正确的视图；
- **严格转换**——id 复用、指向非活动记录的删除或派发都会被拒绝；
- **重启自愈**——活动提醒每次读取都从 `session.events` 折叠重建，所以会话落盘后
  重启即可恢复；`fork` 出的会话只折叠自身后缀，不继承父会话的提醒。

## 装配

```dart
final schedule = provideSessionSchedule(ctx, session: session, sessions: store);
provideScheduleTools(ctx);

// 交付端口由宿主提供：空闲时投递并返回 true，忙时返回 false
provideScheduleRuntime(ctx, deliver: (String text) async => deliverToSession(text));
```

- `SessionSchedule`（服务键 `'schedule'`，`ctx.schedule`）：创建 / 列出 / 删除，
  并在读取与变更前等待一次持久化检查点；无法确认时抛
  `SchedulePersistenceException`（工具层返回 `persistence_uncertain`），而不是声称成功。
- `ScheduleRuntime`（服务键 `'scheduleRuntime'`，`ctx.scheduleRuntime`）：分段定时器
  唤醒、每次醒来重新采样墙钟、构造固定 framing，**只在投递入队成功之后**才写入派发
  记录。投递被拒绝或失败时记录保持活动、不写任何东西；派发记录写入失败则进入故障态
  并停止派发（消息可能已经入队，不能重发）。

## 选择器

| 选择器 | 语义 |
|---|---|
| `after_seconds` | 正安全整数秒的延迟 |
| `at` | 显式偏移的 RFC 3339 串，或 `{date, time, time_zone}` 本地日历对象 |
| `every_seconds` | 不小于 300 秒的固定间隔，与创建锚点对齐 |

`time_zone` 只接受 `UTC` 或 IANA `Area/Location` 名（IANA 名必须含 `/`，因此
`CST` 会被拒绝）。夏令时缺口内的本地时刻不存在，直接拒绝；重叠时取较早的那个瞬时。
提交的偏移量永远不会进入持久记录——只保留规范化后的 UTC 瞬时。

固定间隔提醒**只追赶最新一次**而从不回放积压：决策用整数运算直接推进到第一个未来
目标。一次性提醒优先于固定间隔批次，且一次只交付一条；批次内每条记录只取最新一个
发生时点，整批共用同一个决策时点。

## 限制

- 交付仅限原会话：没有外部通知渠道；
- 重试由活动驱动（轮次结束、定时唤醒、下一次工具调用），不额外起私有重试定时器；
- 同步投递成功之后、派发记录写入之前发生崩溃，可能造成一次重复提醒；
- 运行时只装配给显式提供的 `SessionSchedule`，不会自行扫描或唤醒其它会话。
