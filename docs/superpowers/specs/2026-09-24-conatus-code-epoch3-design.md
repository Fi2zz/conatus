# nava 三期：后台任务执行器 + 消息队列 + delta 快照 — 设计

日期：2026-09-24
状态：已实施（2026-09-24，见实现计划；后台任务 keep_alive_on_exit 与 delta 哈希级检测留作后续）
范围：`packages/conatus_code` 子模块（后台任务与消息队列不触碰框架；delta 快照在既有 checkpoint 模块内演进）

## 背景

三期三个能力补齐 nava 的工程化短板：

1. **后台任务**：模型或用户需要跑长命令（编译、测试、下载）而不阻塞对话——
   `ShellExecutor.start` 能力缝与 `[background]` 配置**已存在但从未消费**。
2. **消息队列**：busy 时输入被拒（「正在回复，请稍候」），无法排队追问。
3. **delta 快照**：checkpoint 每轮全量复制工作区，大仓库成本高。

## A. 后台任务执行器（spec #4）

### 决策记录

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 执行通道 | 复用 `'shell'` 缝的 `ShellExecutor.start(spec)` → `ShellProcess` | 能力缝已定义且 Local/沙箱两实现都实现了 `start`；沙箱内后台进程自动获得 CommandPolicy 形状裁决 + seatbelt 隔离 |
| 任务追踪 | 新增 `BackgroundTaskService`（nava 侧，根上下文服务） | `conatus_tasks` 的 TaskCenter 是「当前有哪些任务」的会话级追踪；后台任务要跨会话存活并持有 `ShellProcess` 句柄，独立服务更简单 |
| 并发上限 | 读 `[background] max_running_tasks`（缺省 4），超限拒绝 | 已有配置，消费它 |
| 退出语义 | 任务随 nava 进程退出而结束；`keep_alive_on_exit` **本期不实现**（保留配置） | 真 detach（setsid/nohup）需额外进程管理，v1 收窄 |
| 产出读取 | 服务内累计各任务输出（readOutput 增量 + 累加），`background_output` 读全量 | readOutput 是消费式增量，直接暴露会让模型拿不全 |
| 工具形态 | 4 个工具：`run_command_background`（high）/ `list_background_tasks`（low）/ `background_output`（low）/ `background_kill`（medium） | 工具名与 run_command 系对齐 |
| 用户命令 | `/background [list|output <id>|kill <id>]` | 与 `/team`/`/task` 同风格 |
| 审批 | `run_command_background` 走 high 风险审批链；`background_kill` medium | 启动是副作用，kill 也影响进程 |
| 记录保留 | 完成/被杀任务保留最近 20 条（内存） | 防无限增长 |

### 架构

```
[background] config（已有）→ BackgroundTaskService
                                   ├─ start(command, cwd): shell.start(resolve(...)) → bg-<n>
                                   ├─ list(): id/command/status/exitCode/elapsed
                                   ├─ output(id): 累计输出（readOutput 增量叠加）
                                   └─ kill(id): process.kill()
4 个工具 + /background 命令 → 服务
```

- task id：`bg-<自增序号>`。
- `run_command_background` 参数：`command`（必填）、`cwd`（可选）；返回 `bg-<n>` + 提示「后台已启动，用 list_background_tasks / background_output 查看」。
- 沙箱：命令照常过 `CommandPolicy`（管道/重定向放行，`&&`/`;`/`$()` 拒绝）；`start` 失败（被拒）返回 `RejectedShellProcess`，工具按失败映射。
- `ShellProcess.done` 落定时把任务标记 completed，不回收（记录保留 20 条）。

## B. 消息队列（spec #15）

### 决策记录

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 入队范围 | **只排队用户输入**（文本 + 附件） | cron/提醒的投递在 busy 时已返回 false 由调度器重试，语义不变 |
| 队列容量 | 上限 20 条，满了拒绝并提示 | 防失控 |
| 出队时机 | `_afterTurn` 收口后依次投递下一条（unawaited） | 轮次之间自然衔接 |
| Esc 打断 | 取消当前轮 + **清空队列** | 打断 = 放弃当前对话流，排队消息一并作废（明确提示） |
| 会话切换 | `_unbind` 清空队列 | 排队消息属于原会话上下文 |
| 入队反馈 | system 消息「已排队（第 N 条），当前轮结束后依次处理」 | 用户可见 |
| busy 判定 | submit() 入口：busy && agent 就绪 → 入队；agent 未就绪仍拒绝 | 未绑定会话不该排队 |

### 架构

```
submit(text, attachments)
 ├─ busy? → 入队 _queue（上限 20），提示已排队
 └─ 否则跑轮
_afterTurn（busy=false 后）→ 队列非空 → unawaited(submit(下一条))
interrupt() → cancel + 清空队列 + 提示
_unbind() → 清空队列
```

- 队列元素：`(String text, List<TuiAttachment> attachments)`。
- cron/提醒投递路径（`deliverCron` / `_deliverReminder`）不改：仍 busy 时返回 false。

## C. delta 快照优化（checkpoint 已知边界）

### 决策记录

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 模型 | **turn 0 全量 base + 各轮相对 base 的差量**（differential backup） | 每轮只复制变化文件，stat 遍历成本低 |
| base 保留 | turn 0 永不 prune（回滚正确性的锚） | 差量自包含于 base，prune 任意差量不影响其他差量恢复 |
| prune 语义 | 保留 turn 0 + 最近 `keep-1` 个差量（`keep` 仍是回滚点数；`<=0` 不限） | 与旧 keep 语义等价的回滚点数量 |
| 变化检测 | 相对 base 的 mtime + size 比对（不一致即复制） | 快；文档注明「保留 mtime+size 的内容修改会漏检」（罕见，可接受） |
| 删除记录 | 差量 manifest 记 `deleted` 列表 | 恢复时删除 |
| 恢复 | base 全量铺底 + 差量覆盖（changed）+ 删（deleted）+ 删当前多余文件 | 两步合成目标状态 |
| 清单格式 | 单 `manifest.json` 带 `kind: base|delta`；base 记录每个文件 mtime/size | 统一读取 |
| 变更面 | 全部在 `CheckpointStore` / `CheckpointManifest` 内；manager/命令/配置不变 | 内部优化 |

### 架构

```
turn 0:  base manifest {kind, files:[{path,mtimeMs,size}], lastEventId}
turn N>0: delta manifest {kind, changed:[...], deleted:[...], lastEventId}
          Δ 目录只存 changed 文件（相对 base 变化/新增）
snapshot(N>0): 遍历工作区 → 与 base stats 比对 → 复制 changed、记 deleted
restore(N):  base 铺底 → (N>0 时) 差量覆盖/删除 → 删当前多余
prune:       删最旧差量（base 除外），保留最近 keep-1 个
```

- `CheckpointStore.list` 改为返回 `List<CheckpointInfo>`（turn + 有效文件数，base 用全量数、差量用 base+changed−deleted），manager 直接消费。
- 兼容：旧版检查点目录（无 kind 字段）按 base 读取（files 为相对路径列表）——升级不破坏已有检查点。

## 文件结构

| 文件 | 职责 |
|------|------|
| `lib/src/background/background_tasks.dart` | **新**：`BackgroundTaskService`（start/list/output/kill，maxRunning 与记录保留） |
| `lib/src/background/background_tools.dart` | **新**：4 个工具 + `provideBackgroundTools` |
| `lib/src/tui/tui_controller.dart` | `/background` 命令；消息队列（字段 + submit/afterTurn/interrupt/unbind 接线） |
| `lib/src/tui/tui_commands.dart` | `/background` 表项 |
| `lib/src/checkpoint/checkpoint_types.dart` | manifest 扩 kind/stats/changed/deleted；`CheckpointInfo` |
| `lib/src/checkpoint/checkpoint_store.dart` | base/delta 快照、两步恢复、新 prune、list→CheckpointInfo |
| `lib/src/tui/tui_app.dart` | 装配 `BackgroundTaskService`（`[background]` 配置） |
| `bin/conatus_code.dart` | 传 `background` 配置 |
| 测试 | `test/background/`、`test/tui/tui_background_command_test.dart`、`test/tui/tui_message_queue_test.dart`、`test/checkpoint/checkpoint_delta_test.dart`（store v2 改写） |

## 测试策略

- **后台**：fake ShellExecutor（脚本化 start 返回假 ShellProcess）→ 服务 start/list/output/kill、上限拒绝；工具映射；沙箱拒绝路径（RejectedShellProcess）。
- **队列**：busy 入队、收口出队依次执行、容量上限、Esc 清空、会话切换清空、cron 投递不排队。
- **delta**：turn 0 base 全量；turn 1 只存变化文件 + deleted 记录；恢复 = base+delta 合成（覆盖/删除/补回）；prune 保 base + keep-1 差量；旧格式兼容读。

## 已知边界

- 后台任务随进程退出而结束（无 keep_alive_on_exit）；任务输出上限沿用 shell 执行器预算（截断标记 lossy）。
- delta 变化检测用 mtime+size，极端的「内容变但 mtime/size 不变」会漏检（文档注明）。
- 消息队列是控制器内内存态：进程重启后不保留排队内容。
