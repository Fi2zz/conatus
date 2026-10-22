# 方案：收敛为单一产品 nava——把 cowriter 增量并入 conatus_code 并归档

> 日期：2026-10-22 · 状态：已批准，待实现
>
> 背景：`packages/conatus_code` 与 `packages/cowriter` 是同一 fork 上的两个产品，
> 代码重合约 95%（各约 4.1 万行 Dart、122 个测试文件）。分叉后 conatus_code 的
> XERJ 提交已被 cowriter 等价镜像，cowriter 额外有故事层、steering、diff apply
> 重构、品牌隔离与编码工具面删减；conatus_code 额外保留编码工具面。
>
> 目标：**只保留 nava（conatus_code）一个产品**，把 cowriter 的有价值增量并入，
> 之后只维护一份代码；cowriter 仓库归档。

## 1. 目标与成功标准

### 目标

1. nava 成为唯一维护线：包名 `conatus_code`、二进制 `nava`、品牌、配置目录
   `~/.nava`、项目上下文 `NAVA.md` 全部不变。
2. 吸收 cowriter 的通用增量：故事层（可选）、轮内 steering、diff apply 纯函数面。
3. nava 默认启动行为与合并前完全一致：故事层默认关闭。
4. cowriter 仓库归档，父仓移除该子模块。

### 成功标准

- `dart analyze --fatal-infos` 干净。
- `dart test` 全绿：现有 909 用例 + 移植的 story / steering 用例。
- `bash tool/build_binary.sh && ./dist/nava --version` 成功。
- 默认配置启动：不创建 `doc` 服务、不装文件监听、编辑直接落盘。
- `[story] enabled = true`：`/story` 时间轴与待定补丁 apply/reject 可用；
  headless 仍直写（无人审）。
- 父仓移除 cowriter 后 `dart pub get`、workspace 解析、CI 消费链照常。

### 非目标

- **不改包名**：`conatus_code` 保持，避免约 280 文件 import 翻新与后续 diff 噪音。
- **不做数据迁移工具**：不自动搬 `~/.cowriter` → `~/.nava`；文档给映射，用户手动迁移。
- **不恢复编码工具面**：nava 本来就有 git / shell / run_tests / run_code 与
  `/commit`、`/review`，全部保持不变。
- **不移植 cowriter 的品牌契约**：`~/.cowriter`、`COWRITER_HOME`、`COWRITER.md`、
  `COWRITER_VERSION`、`dist/cowriter` 随归档废弃。
- **不做插件化/profile 抽象**：单一产品不需要 `ProductProfile`。

## 2. 现状依据

| 维度 | conatus_code | cowriter |
|---|---|---|
| Dart 文件 / 行数 | 283 / 41,326 | 280 / 41,893 |
| 测试文件 / 用例 | 122 / 909 | 122 / 886 |
| 分叉点 | `8486dc8` | 同左 |
| 独有增量 | 编码工具面（git / shell / run_tests / run_code、`/commit`、`/review`、playground） | story（11 文件 1,283 行 + 8 测试 1,537 行）、`conatus_doc` 依赖、steering、`diff/apply.dart` |
| conatus 钉版 | `61ab5d9` | `7714a43`（更新，含 doc fork 接线） |

树级差异约 140 文件，其中约 100 文件仅为改名后的 import 排序与品牌字符串；
语义冲突集中在 `tui_controller.dart`（13 hunk）、`tui_app.dart`（10 hunk）与
config / hooks / project_context / headless / list_files / glob。

## 3. 设计

### 3.1 故事层：移植 + 默认关闭

新增配置 `[story] enabled`（`bool`，缺省 `false`）：

```toml
# 人机双写故事层（可选）：编辑即补丁、事前审阅、/story 时间轴。
# 关闭时行为与普通编码会话完全一致。
# [story]
# enabled = true
```

- `StoryConfig` 加入 `ConatusCodeConfig`；`ConfigParser._readStory` 读取；
  `config_loader.dart` 模板写入注释段。
- 关闭时：
  - 不调用 `provideStory`，因此没有 `doc` / `storyReview` / `storyNotices` 服务；
  - 不创建 `story-log` 会话日志目录；
  - 不注入 `story-ops` prompt；
  - 不装工作目录轮询监听。
- 开启时（TUI）：`provideStory(ctx, sessionId:, session:, review: true)`——
  与 cowriter 现状一致，写工具先成待定补丁。
- 开启时（headless）：`provideStory(..., review: false)`——无人审，保持直写。
- `/story` 命令常驻：未启用时返回一行提示（指向 `[story] enabled`），不抛错；
  这样命令发现性保留，且不依赖配置分支改动命令表。

### 3.2 通用增量：无条件合入

1. **`diff/apply.dart` 纯函数面**
   - 新增 `apply.dart`：`PatchContextException`、`applyDiffFile`、`applyEditText`。
   - `apply_patch.dart` 删除私有 `_applyHunk` / `_PatchContextError`，改调
     `applyDiffFile`。
   - `preview.dart` 删除私有 `_applyEdit`，改调 `applyEditText`。
   - 目的：工具实现与事前审阅共用同一语义，避免两套实现漂移。
2. **轮内 steering**
   - `tui_controller.dart` 绑定会话后设置 `_agent?.steering = _takeQueuedForSteering`；
   - `_takeQueuedForSteering` 合并两个来源：先 `storyNotices`（人的编辑通报），
     后排队消息；story 关闭时 `storyNotices` 不存在，自动退化为纯队列注入；
   - 轮末队列投递保留为兜底路径；
   - 移植 `tui_steering_test.dart`、`tui_input_queue_test.dart`（与现有
     `tui_message_queue_test.dart` 合并去重，不重复断言同一行为）。
3. **prompt / 文档**
   - `steering` prompt section 无条件注入（对编码场景也是正向：最新用户消息优先）。
   - `story-ops` prompt section 仅在 story 启用时注入。
   - README 增加「人机双写故事层（可选）」小节；新增 `docs/story.md` 说明补丁模型、
     `/story` 子命令、开关与数据落点。

### 3.3 依赖与钉版

- `packages/conatus_code/pubspec.yaml`：
  - `dependencies` 增加 `conatus_doc`（git + path）；
  - `dependency_overrides` 增加 `conatus_doc`，22 条变 23 条；
  - `conatus` 及全部 `conatus_*` 的 `ref` 统一刷新到父仓 `origin/master` 的
    单个 commit（至少包含 `7714a43` 的 doc fork 接线），并在实现提交中记录实际 SHA。
- 刷新后跑全量测试；若父仓 master 引入不兼容变更，允许钉到 `7714a43`（已知可用）。

### 3.4 父仓清理

1. 移除子模块：`git submodule deinit -f packages/cowriter`、`git rm -f packages/cowriter`，
   清理 `.git/modules/packages/cowriter`。
2. `.gitmodules` 删除 cowriter 条目。
3. `tool/setup_code_filter.sh` 的 target 列表只保留 `packages/conatus_code`。
4. `AGENTS.md`：
   - §2 子模块从 ×2 改 ×1，删除 cowriter 行；
   - §7 子模块工作流删除 cowriter 的二进制/构建说明；
   - §10 删除 cowriter 现状段落。
5. 根 `README.md`：删除「packages/cowriter 同为独立子模块」段落。
6. workspace glob 会自动跳过已删除目录，无需改 `pubspec.yaml`（确认注释仍准确）。

### 3.5 cowriter 归档

1. 在 cowriter 仓库新增 `ARCHIVED.md`，写清：
   - 归档日期与决定：收敛为单一产品 nava，降低双份代码的维护成本；
   - 增量去向：story 已并入 `conatus_code`（附合并提交 SHA），steering / diff apply
     同步合入；
   - 迁移指引：`~/.cowriter/config.toml` → `~/.nava/config.toml`、会话与
     `story-log` 目录映射、`COWRITER.md` → `NAVA.md`；
   - 明确「本仓库不再接受改动，问题请提到 conatus 仓库」。
2. `README.md` 顶部加醒目的归档横幅，指向 `ARCHIVED.md` 与 nava。
3. 推送后执行 `gh repo archive Fi2zz/cowriter`（只读，保留历史）。
4. 归档提交必须先于父仓 gitlink 移除推送。

## 4. 文件级改动清单

### conatus_code（子模块）

| 文件 | 动作 |
|---|---|
| `pubspec.yaml` | 加 `conatus_doc`；23 条 override；ref 全量刷新 |
| `lib/src/config/config_schema.dart` | 新增 `StoryConfig`，挂到 `ConatusCodeConfig` |
| `lib/src/config/config_parser.dart` | 新增 `_readStory()`，parse 时读取 |
| `lib/src/config/config_loader.dart` | 模板增加 `[story]` 注释段 |
| `lib/src/story/*.dart` | 从 cowriter 移植 11 文件 |
| `lib/src/diff/apply.dart` | 新增 |
| `lib/src/diff/preview.dart` | 改用 `applyEditText` |
| `lib/src/tools/apply_patch.dart` | 改用 `applyDiffFile` |
| `lib/src/tui/tui_app.dart` | story 装配 + `story-log` + prompt 条件注入 |
| `lib/src/tui/tui_controller.dart` | story 命令接线、`provideStory`、steering |
| `lib/src/tui/tui_commands.dart` | `/story` 命令条目 |
| `lib/src/headless/headless_runner.dart` | story 装配（review=false） |
| `lib/conatus_code.dart` | 导出 story / apply 公开 API |
| `test/story/*_test.dart` | 移植 8 文件 |
| `test/tui/tui_steering_test.dart` | 移植 |
| `test/tui/tui_input_queue_test.dart` | 与现有消息队列测试合并 |
| `test/config/config_story_test.dart` | 新增：默认 false、读取 true、模板存在 |
| `test/tui/tui_story_wiring_test.dart` | 新增：默认关闭无 `doc` 服务且编辑直写；开启时成待定 |
| `README.md` / `CHANGELOG.md` / `docs/story.md` | 文档 |

### 父仓

| 文件 | 动作 |
|---|---|
| `.gitmodules` | 删除 cowriter 条目 |
| `packages/cowriter/` | 移除 gitlink 与本地子模块目录 |
| `tool/setup_code_filter.sh` | target 只留 conatus_code |
| `AGENTS.md` / `README.md` | 子模块与产品说明改为单一 nava |
| `docs/superpowers/specs/2026-10-22-cowriter-merge-into-nava-design.md` | 本文件 |

### cowriter（归档提交）

| 文件 | 动作 |
|---|---|
| `ARCHIVED.md` | 新增，写清归档原因、增量去向、迁移指引 |
| `README.md` | 顶部归档横幅 |

## 5. 测试策略

1. **配置**：`[story]` 缺省 false；显式 true 解析成功；非法类型抛 `ConfigException`。
2. **行为隔离**：
   - 默认配置下装配 TUI：断言 `ctx.get('doc') == null`、无 `story-log` 目录、
     `write_file` 直接落盘。
   - 开启 story：断言写工具返回「已登记为待定补丁」且文件未变；`/story apply`
     后文件落盘；`/story reject` 后保持原样。
3. **headless**：开启 story 时仍直写，不产生待定补丁。
4. **steering**：生成中插话在下一轮模型请求前注入；队列兜底路径仍工作。
5. **回归**：现有 909 用例全过；`dart analyze --fatal-infos` 干净。
6. **打包**：重建 `dist/nava`，`--version` 输出 `nava <version>`。

## 6. 风险与回滚

| 风险 | 缓解 |
|---|---|
| conatus 钉版刷新引入行为变化 | 全量测试 + 冒烟；必要时退回 `7714a43` |
| story 与 checkpoint/rewind/fork 的交互回归 | 移植 cowriter 既有 story 测试；补 `/rewind` + story 用例 |
| 关闭路径漏判导致默认行为变化 | 专项断言「默认关闭无 doc 服务、编辑直写」 |
| 子模块移除破坏 workspace 解析 | 移除后跑 `dart pub get` + 根测试 + CI 消费链 |
| 归档顺序错误导致链接失效 | 先推 cowriter 归档提交，再推父仓 gitlink 移除 |

**回滚**：实现集中在 conatus_code 一个提交；`git revert` 即可恢复。父仓侧为
`.gitmodules` 与文档改动，同样可 revert；cowriter 仓库只多一个归档提交，不影响代码。

## 7. 执行顺序

1. conatus_code：依赖/钉版 → 配置 → story 移植 → 接线 → 通用增量 → 测试 → 文档。
2. `dart analyze --fatal-infos` + `dart test` + 重建二进制；提交并推送 conatus_code。
3. cowriter：写 `ARCHIVED.md` + README 横幅；提交推送；GitHub archive。
4. 父仓：移除子模块、改脚本与文档、同步 gitlink；提交推送。
5. 验证父仓 `dart pub get` 与根测试；确认 CI。

## 8. 验收清单

- [ ] `[story] enabled` 默认 false，模板与 README 有说明
- [ ] 默认配置：无 `doc` 服务、无 watcher、无 `story-log`、编辑直写
- [ ] 开启后：待定补丁、apply/reject、`/story` 时间轴可用
- [ ] headless 开启 story 仍直写
- [ ] steering 轮内注入与队列兜底均有测试
- [ ] `dart analyze --fatal-infos` 干净
- [ ] `dart test` 全绿（含新增用例）
- [ ] `dist/nava` 重建且 `--version` 正确
- [ ] 父仓无 cowriter 子模块，`dart pub get` 与根测试通过
- [ ] cowriter `ARCHIVED.md` 写清归档原因与迁移指引，仓库已 archive
