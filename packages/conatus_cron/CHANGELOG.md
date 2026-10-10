# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

初始实现——定时任务插件，语义移植
[dsh-cron](https://github.com/ZhuoSir/dsh-cron)（不含其 web 部分）：

- 四种调度规则：`at`（一次性）/ `every`（固定间隔）/ `daily`（本地时间，
  错过补发一次）/ `cron`（标准 5 段表达式，Vixie 语义）
- `provideCronTools`：`cron_list` / `cron_add` / `cron_update` / `cron_remove` /
  `cron_history` 五个模型工具；任务绑定当前会话，触发回到原会话执行
- `CronStorage` 抽象端口 + `JsonCronStorage` 本地实现（原子写入、损坏降级），
  `configTasks` 支持配置期静态任务（运行时不可增删改）
- `CronDelivery` / `CronNotifier` 注入端口：投递策略由宿主决定，
  `finishRun` 由装配方显式推进运行记录；通知缺省关闭，平台实现（macOS
  osascript / Linux notify-send）由调用方提供
- 逐条对齐 dsh-cron 语义（每 tick 任务隔离、重启不重发、历史 500 封顶、
  防注入 framing），53 条测试锁定
