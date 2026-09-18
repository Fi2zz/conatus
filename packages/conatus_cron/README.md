# conatus_cron

conatus 的定时任务插件（仅依赖 `conatus_core` 与 `conatus_foundation`）：按
`at` / `every` / `daily` / `cron` 规则调度任务，到点把任务提示以固定 framing
交付给宿主注入的端口执行，运行记录持久化——语义忠实移植
[dsh-cron](https://github.com/ZhuoSir/dsh-cron)（DeepSeek Harness 插件，MIT），
**不含其 web 部分**（管理抽屉、`/cron/api` HTTP 层及配套安全代码）。

## 用法

```dart
final service = provideCron(ctx,
    storage: JsonCronStorage(
      tasksPath: '$dir/cron-tasks.json',
      historyPath: '$dir/cron-history.jsonl',
    ));
provideCronTools(ctx);
final runtime = provideCronRuntime(ctx,
    deliver: (recordId, framing, task) async {
      // 把 framing 投递进目标会话；false 表示暂时无法投递，下个 tick 重试。
      // task 为原始任务，调用方可自行决定如何渲染投递内容。
      return submitToSession(framing);
    },
    // 系统通知为可选注入端口（缺省不通知）。桌面实现由 conatus_tui 提供
    // （systemCronNotifier()：macOS osascript / Linux notify-send），移动端
    // 宿主可注入 flutter_local_notifications 等任意 CronNotifier。
    options: CronRuntimeOptions(notifier: systemNotifier));

// 任务 turn 执行完后推进运行记录（装配方负责调用）：
runtime.finishRun(recordId, ok: true, excerpt: '…');
```

模型在对话中用自然语言管理任务（「每周一早上 9 点提醒我交周报」），Agent 调用
`cron_list` / `cron_add` / `cron_update` / `cron_remove` / `cron_history`
五个工具；任务经 `cron_add` 创建时绑定当前会话，触发回到原会话执行。

## 调度规则（每个任务四选一）

| 字段 | 含义 | 示例 |
|------|------|------|
| `at` | 一次性，ISO 8601 时间 | `"2026-08-23T09:00:00+08:00"` |
| `every` | 固定间隔（秒，最小 10） | `3600` |
| `daily` | 每天本地时间 `HH:MM`（错过当天补发一次） | `"09:30"` |
| `cron` | 标准 5 段表达式（分 时 日 月 周，本地时间） | `"0 9 * * 1"` = 每周一 09:00 |

cron 表达式支持 `*`、列表、范围与步进（`*/n`、`a-b/n`、`a/n` 为 Vixie 语义）；
日、周同时受限时任一匹配（标准 cron 语义）。

## 存储能力缝

[CronStorage] 是抽象端口（加载/保存任务快照与运行历史），本包提供
[JsonCronStorage] 本地文件实现（原子写入、损坏降级）；宿主可实现同一接口接入
任意后端（数据库、远程 KV）。`provideCron` 也可叠加 `configTasks` 静态任务
（`origin: config`，运行时不可增删改）。

## 与 dsh-cron 的差异

- **未移植**：客户端抽屉 UI、`/cron/api` HTTP API、trust fence（DNS 重绑定防护）。
- **交付形态**：dsh 用 `agent.followup()` + 会话事件流自动推进运行状态；本包是
  `CronDelivery` 注入端口 + 装配方显式调 `finishRun`（conatus 没有等价事件流，
  且这让投递策略完全由宿主决定）。
- **通知**：系统通知为可选注入端口，默认关闭。本包只定义抽象 `CronNotifier`
  端口（标题 + 正文 + 原始任务），不做平台实现；macOS / Linux 实现（`osascript` /
  `notify-send`）由 conatus_tui 提供（`systemCronNotifier()`），iOS / Android /
  Windows 由宿主注入任意 `CronNotifier`（如 flutter_local_notifications）。
- 其余语义（四种规则、daily 补发、每 tick 任务隔离、重启不重发、历史 500 封顶、
  防注入 framing）逐条对齐，53 条测试锁定。

## 注意

- **每次触发都是一轮真实模型调用**，消耗 token；任务质量取决于 prompt，Agent
  的工具权限在任务执行时同样生效。
- 规则计算不读墙钟（`now` / `startedAt` 全参数化），注入 `clock` 可回放与测试。
- 定时器随上下文 `dispose` 自动停表，不删除任何持久记录。
