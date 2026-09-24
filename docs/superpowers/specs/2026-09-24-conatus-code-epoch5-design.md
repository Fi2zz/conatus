# nava 五期：! shell 模式 + /review + lint-on-edit — 设计

日期：2026-09-24
状态：已实施（2026-09-24，见实现计划）
范围：`packages/conatus_code` 子模块

## 背景

按中高 ROI 三连：`!` 快捷 shell（省流高频）、`/review` 质量前移、lint-on-edit
（模型改完即自检，错误当场闭环）。

## A. `!` shell 模式

### 决策记录

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 触发 | 输入行以 `!` 开头 → 直接执行，不进模型 | 对齐 Claude Code / aider `/run` |
| 执行通道 | `'shell'` 缝（沙箱 + CommandPolicy 照常生效） | 用户直发也受护栏约束 |
| 审批 | 不挂审批 | 用户亲手输入即已授权 |
| 输出 | 结果进 transcript（system 角色）：成功显示 stdout、失败合并 stderr+退出码 | 可见可回溯 |
| 超时/上限 | 60s 超时 + shell 执行器输出上限 | 防挂死 |
| `!!` | 重跑上一条 `!` 命令 | 高频补遗 |
| busy | 有在途轮次时拒绝 | 避免与流式渲染打架 |

## B. `/review`

### 决策记录

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 形态 | `/review` 提交固定审查提示词，模型经 git_diff/git_status 自查 | 复用 Agent Loop，与 `/commit` 衔接 |
| 审查范围 | 未提交改动（git diff）；提示词明确「只审不改」 | 提交/提 PR 前自检 |
| 输出 | 结构化发现清单（命名/边界/安全/性能） | 直接可读 |

## C. lint-on-edit

### 决策记录

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 触发 | 工具中间件：`write_file` / `edit_file` / `apply_patch` 成功返回后 | 模型改完即自检 |
| linter 映射 | 启动时按 workdir 探测：`pubspec.yaml`→`dart analyze`；`package.json`→`eslint .`（有 eslint 配置才用）；`go.mod`→`go vet ./...`；`Cargo.toml`→`cargo check`；`[lint] command` 可覆盖 | 小映射表覆盖主流 |
| 去抖 | 每 `debounce_seconds`（缺省 10s）最多跑一次 | 多文件连续编辑不连跑 |
| 结果 | 告警截断（2000 字符）追加进工具结果 content（模型当场可见） | 闭环 |
| 失败语义 | linter 不存在/超时/报错 → 静默跳过或追加「Lint 未执行」，不打断主结果 | 护栏 |
| 配置 | `[lint] enabled`（缺省 true）、`command`（覆盖）、`debounce_seconds` | 可关可换 |
| 执行 | 走 `'shell'` 缝（沙箱） | 与 run_command 同约束 |

## 文件结构

| 文件 | 职责 |
|------|------|
| `lib/src/tui/tui_controller.dart` | `!` 分支 + `_runShellBang`；`/review` 命令 |
| `lib/src/tui/tui_commands.dart` | `/review` 表项 |
| `lib/src/lint/linter.dart` | **新**：`LinterService`（探测/去抖/运行/中间件） |
| `lib/src/config/config_schema.dart` / `config_parser.dart` / `config_loader.dart` | `[lint]` 表 |
| `lib/src/tui/tui_app.dart` | 装配 `'linter'` 服务 + 中间件 |
| `bin/conatus_code.dart` | 传 `config.lint` |
| 测试 | `test/tui/tui_shell_bang_test.dart`、`test/tui/tui_review_test.dart`、`test/lint/linter_test.dart`、`test/config/config_lint_test.dart` |

## 测试策略

- bang：`!echo hi` 执行并上屏；`!!` 重跑；busy 拒绝；`!` 空用法；沙箱拒绝映射。
- review：/review 触发一轮且提示词含「审查」与 git diff。
- lint：探测映射（pubspec→dart analyze）；编辑工具后追加告警；去抖不连跑；`[lint] enabled=false` 不触发；命令覆盖。
