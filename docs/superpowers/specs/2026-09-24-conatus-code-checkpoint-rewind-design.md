# nava checkpoint/rewind — 设计

日期：2026-09-24
状态：已实施（v1 文件回滚 + v2 对话回滚均已完成，见实现计划）
范围：`packages/conatus_code` 子模块；v2 对话回滚可能触及 `conatus_foundation`（`SessionStore.adopt`，见下）

## 背景

conatus_core 的核心卖点是**可逆效应**（时间可组合性：副作用登记撤销、LIFO 回滚）。
但 nava 目前没有用户可见的**文件级回滚**：模型改坏了工作区，只能靠 git 或手工恢复。
RecoveryService 的快照是**会话事件快照**（对话日志），与工作区文件状态无关。

用户痛点：模型一轮工具调用（write_file / edit_file / apply_patch / run_command）
可能改乱多个文件，无法一键回到改之前的状态。checkpoint/rewind 把这个能力做成
一等公民，与框架的可逆哲学对齐。

## 决策记录

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 快照内容 | **工作区文件**（sandbox 根 = workdir） | 回滚的目标是文件状态 |
| 排除项 | `<projectDir>`（缺省 `.conatus`，含 checkpoints 自身，防递归）与 `.git` 一律排除；`[checkpoint] ignore` 可追加（相对路径前缀） | `.conatus` 是数据目录；`.git` 有自身历史，快照它又大又无意义 |
| 快照时机 | 会话绑定时（**turn 0**，记录初始状态）+ 每轮收口（`_afterTurn`）后 | 初始快照使 `/rewind` 能回到「全部轮次之前」 |
| 存储 | **普通文件复制**到 `<projectDir>/checkpoints/<sessionId>/<turn>/`，每个检查点目录带 `manifest.json`（相对路径清单） | **硬链接不安全**：模型经 `run_command` 原地写文件（`sed -i` 等）会共享 inode、把快照内容也改掉——只有原子写（rename）才有写时复制。正确性优先 |
| 存储压缩 | 2026-09-24 追加：每个检查点**打包成单个无扩展名归档文件**（`<会话>/<sha256 哈希名>`，自定义容器：gzip(清单JSON+条目流)，`dart:io` 内置 GZipCodec，零新依赖），**不保留目录结构**、内容非明文、**文件名不可读且无 `.gz` 扩展名**（轮次只记录在归档头与会话级 gzip `index`，`list`/`prune` 只读索引不逐个解包）；读时自动回退旧版目录树检查点、索引缺失自动重建 | 用户反馈明文副本令人不安，要求「整个项目压缩成一个文件而不是保留结构输出」，并希望文件名不可读、看不出是 gzip；单文件同时减小磁盘占用 |
| 保留策略 | 每会话保留最近 `[checkpoint] keep` 个检查点（缺省 5，含 turn 0）；`0` = 不限；超出删最旧 | 磁盘成本受控 |
| 回滚目标 | `/rewind [N]`：回滚 N 轮（缺省 1 = 上一个完成的轮次）；N 超出可用时钳制到最早 | 与直觉一致 |
| 恢复语义 | 目标检查点的文件覆盖当前；当前存在而检查点没有的文件**删除**；检查点有而当前没有的恢复 | 工作区状态对齐该检查点（rsync 式） |
| 对话回滚 | **v1 不做**：保留当前会话与对话，/rewind 后追加一条 system 说明「文件已回滚到第 N 轮，可让模型按当前文件状态继续/重做」 | v1 收窄到文件状态；对话回滚涉及 fork/会话注册的框架改动（见下「v2 对话回滚」） |
| 审批 | `/rewind` 是**用户斜杠命令**，不是模型工具 → 不挂审批链 | 用户显式操作，非模型发起的副作用 |
| Plan Mode | 不拦截用户命令 | 同上 |
| 沙箱 | 快照与恢复走 **dart:io 直连**（不经 `'fs'` 接缝 / 不被 fs jail 拦截），与 recovery/sessions 同一信任域 | fs jail 是模型面的守卫，防的是模型乱写；恢复是应用级维护操作。恢复只触碰 workdir 内文件 |
| 模型工具 | v1 不提供 rewind 工具（模型不能自助回滚） | 收窄范围；模型要撤销自己改动用 git 或让用户 `/rewind` |
| 大目录 | 由 `[checkpoint] ignore` 手动排除（如 `node_modules` / `build`），默认不自动跳 | 不过度猜测；硬编码黑名单会误伤 |
| 快照失败语义 | 快照失败只提示不打断轮次（与 recovery 快照同姿态）；回滚失败不触碰文件并提示 | 护栏不能拖垮主链路 |

## 架构

### 配置（`[checkpoint]` 表）

```toml
[checkpoint]
enabled = true   # 是否每轮快照；false 时 /rewind 不可用
keep = 5         # 每会话保留最近 N 个检查点（含 turn 0）；0 = 不限
ignore = []      # 额外忽略的相对路径前缀（如 "node_modules"、"build/"）
```

config 层新增 `CheckpointConfig`（schema）+ `_readCheckpoint()`（parser）+ 模板注释示例。

### 快照

1. 遍历 workdir（dart:io 递归），排除：`<projectDir>` 整树、`.git` 整树、
   `[checkpoint] ignore` 前缀匹配的相对路径；**符号链接跳过**（防逃逸）。
2. 建 `<projectDir>/checkpoints/<sessionId>/<turn>/`，逐文件 `File.copy`
   保留相对路径；目录下写 `manifest.json`（相对路径列表 + 各文件字节数）。
3. 快照前先 prune：保留最近 `keep` 个，删更旧的检查点目录。

### 恢复（`/rewind [N]`）

1. 读 `<sessionId>` 的检查点列表，目标 = 当前轮次 − N（钳制到最早可用）。
2. 读目标 `manifest.json`：
   - 清单内路径 → 检查点文件复制回 workdir（覆盖当前）；
   - 当前 workdir 存在但不在清单 → 删除；
   - 清单有而当前没有 → 自动由第 2 步覆盖补齐。
3. 追加 system 消息：`已回滚工作区到第 <turn> 轮（恢复 X 个、删除 Y 个文件）。`
4. 不切会话、不改对话。

### 轮次计数

控制器持 `_turnCount`（每次绑定会话复位为 0，`_afterTurn` 里自增后快照）。
快照目录名即轮次序号（turn 0 = 初始）。

### 命令

- `/rewind [N]`：回滚 N 轮（缺省 1）。
- `/rewind list`：列出本会话可用检查点（轮次 + 时间 + 文件数），不执行回滚。
- 无检查点（未启用 / 无历史）时提示「没有可回滚的检查点」。
- busy（有在途轮次）时拒绝执行。

## 与既有机制的交互

- **沙箱**：快照/恢复用 dart:io 直连，绕开 fs 接缝——`layers.fs`（JailedFileSystem）
  只约束模型工具；恢复的目标文件都在 workdir（沙箱根）内，语义上不越权。
- **权限/审批**：不挂中间件；`/rewind` 全程用户侧。
- **MCP**：MCP server 的工作目录在 workdir 外，不在快照范围（只快照 workdir）。
- **cron/提醒/技能**：它们也走 `submit()` → `_afterTurn`，同样产生检查点——
  检查点按轮次编号，回滚到的是「该轮收口后」的文件状态，语义一致。
- **headless**：`interactive: false` 时不装配快照（无 controller 轮次钩子）；
  若未来要 headless 回滚，另立方案（CLI 参数而非斜杠命令）。

## 文件结构（均在 conatus_code 内）

| 文件 | 职责 |
|------|------|
| `lib/src/checkpoint/checkpoint_store.dart` | 纯文件系统层：快照、恢复、prune、list、manifest 读写（不依赖 controller） |
| `lib/src/checkpoint/checkpoint_manager.dart` | 每会话管理器：轮次计数、绑定/解绑、`/rewind` 编排（store + session 上下文） |
| `lib/src/config/config_schema.dart` | `CheckpointConfig` |
| `lib/src/config/config_parser.dart` | `_readCheckpoint()` |
| `lib/src/config/config_loader.dart` | 模板注释示例 |
| `lib/src/tui/tui_controller.dart` | 持 manager；`_afterTurn` 快照；`/rewind` 命令 |
| `lib/src/tui/tui_commands.dart` | `/rewind` 表项 |
| `test/checkpoint/checkpoint_store_test.dart` | 快照/恢复/prune/manifest/排除项 |
| `test/checkpoint/checkpoint_manager_test.dart` | 轮次计数、`/rewind` 编排、边界 |
| `test/tui/tui_rewind_command_test.dart` | 控制器侧命令行为（busy 拒绝、无检查点提示、恢复报告） |

## 测试策略

- **store**（真实临时目录，dart:io）：
  - 快照排除 `.git` / `.conatus` / ignore 前缀；manifest 与目录内容一致；
  - 恢复：修改/新增/删除三类文件分别验证（覆盖、删除、补齐）；
  - prune：保留最近 N；`keep=0` 不限；`enabled=false` 不写快照；
  - 符号链接跳过；空工作区快照。
- **manager**：turn 0 初始快照；每轮递增；`/rewind` 目标钳制；无检查点提示；
  busy 拒绝。
- **controller**：真实临时 workdir + projectDir 下跑 `/rewind`，断言 transcript
  报告、磁盘文件状态对齐目标检查点。

## 已知边界与后续

- **对话与文件状态短暂不一致**（v1 固有）：回滚后模型上下文里还有被回滚轮的
  工具结果。用 system 说明缓解；用户可让模型重新核对。
- **v2 对话回滚**：`/rewind` 同时把对话回到该轮之前。方案：
  `Session.fork(fromEventId: <检查点记录的 lastEventId>)` + 控制器切到 fork。
  前置：`SessionStore` 需新增 `adopt(Session)`（把外部创建的 fork 注册进仓库，
  约 5 行 + 单测，additive）；fork 会话 id 需规范化（`session_<uuid>`，现有
  `-fork-N` 后缀不满足 `isCanonicalSessionId`，会进不了 `--session`/`--continue`）。
- **存储优化**：普通复制在大工作区（数 GB、node_modules 未排除）成本高。后续可
  做 delta 快照（只存相对上一快照变化的文件）；硬链接方案已论证**不安全**（原地
  写共享 inode），不作为候选。
- **恢复不可撤销**：/rewind 本身不产生快照（它把文件改回旧态）；若用户后悔可再
  `/rewind` 回去吗？不能（旧检查点已被新状态覆盖？不——检查点仍按 turn 编号，
  恢复不删检查点）。明确：**恢复不动检查点目录**，用户可对同一检查点反复
  `/rewind`；但恢复后的「当前状态」不生成新检查点（要生成得等下一轮收口）。
