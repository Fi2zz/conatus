# 方案：nava 工具层安全护栏（读后写 / 重复调用 / 敏感文件）

> 日期：2026-11-23 · 状态：待评审
>
> 范围：`packages/conatus_code`（不修改父仓库 `packages/conatus_agent` /
> `packages/conatus_foundation`）。
>
> 来源：`/Users/fitz/REPO/kimi-code-research` 的 08 / 09 / 16 / 17 篇，
> 结合 nava 现有工具管线（`ToolRegistry` 守卫 / 中间件、fs 版本守卫、
> 权限评估器）做本地化取舍。

## 1. 背景与目标

Kimi Code CLI 的调研文档给出三条可直接落到工具层的安全/成本不变量：

| 调研结论 | 文档 | nava 现状（证据） |
| --- | --- | --- |
| 写/编辑已存在文件必须先在本会话 read，且文件自读后不得变化 | 09 §2–3 | `write`/`edit` 有可选 `expected_version`，但模型不传就直接写；`read` 返回的 `version` 只作提示（`packages/conatus_fs_tools/lib/src/read_file_text.dart`、`write_file.dart`、`edit_file.dart`） |
| 相同工具调用重复达到阈值要熔断，避免空转 | 08 §6 | 无任何重复调用检测 |
| 敏感文件（`.env`、`id_rsa*`、`credentials`）硬阻断而非询问 | 16 §3 | 只有 `read` 的 `.env` 默认 `ask`（`packages/conatus_agent/lib/src/permissions/permission_evaluator.dart`），无私钥/云凭据识别；`.env` 写入在 `ask_when_needed` 下直接放行 |

目标（按优先级）：

1. **防止覆盖用户未提交的修改**：覆盖已有文件前必须读过，且读后未被外部改动。
2. **止住重复调用空转**：连续相同调用先告警、后拒绝，减少长会话 token 浪费。
3. **挡住私钥/凭据与 `.env` 写入**：护栏在审批之前硬拒，不依赖用户是否盯着弹窗。

### 成功标准

- `write` / `edit` / `apply_patch` 覆盖已有文件时，未读过 → 拒绝并提示先 `read`；
  读后文件被外部修改 → 拒绝并提示重读；新建文件不受影响。
- 连续第 3 次完全相同的工具调用仍执行但结果附告警；第 5 次起不再执行。
- `~/.ssh/id_rsa`、`~/.aws/credentials`、项目根 `credentials` 的读写、以及
  `cat ~/.ssh/id_rsa` 这类字面命令一律拒绝；`*.pub` 与 `.env.example` 放行。
- 三项均可通过 `[safety]` 配置独立关闭；关闭后行为与当前完全一致。
- `dart analyze --fatal-infos` 通过，`packages/conatus_code` 全量测试通过，
  `dist/nava` 重新构建。

### 非目标

- 不做 `select_tools` 动态工具披露、工具并行调度、Hooks 事件扩展、git 工作区
  写操作自动放行（见 §12 后续项）。
- 不把护栏当安全边界：`bash` 里的变量拼接、`sh -c "$CMD"`、读脚本再执行仍可
  绕过（调研 16 篇也明确记录了同类盲区）。护栏只覆盖工具参数里的字面路径。
- 不修改父包对 `.env` 读的 `ask` 语义（保留 OpenCode 对齐）。

## 2. 关键决策

| 决策点 | 结论 | 理由 |
| --- | --- | --- |
| 挂载阶段 | 全部落在 `ToolGuard`（同步、先于所有中间件） | `_dispatch` 顺序是「校验 → 守卫 → 中间件 → 执行体」；守卫天然在审批弹窗之前，且 `copyPipelineTo` 会把守卫复制给子代理注册表 |
| 守卫同步约束 | 读台账检查用 `FileStat.statSync`，不引入异步守卫 | 不改 `ToolGuard` typedef（父包零改动） |
| 路径身份 | 统一用「canonical 绝对路径」做台账键 | 复用 nava 已有 canonical 解析能力（符号链接/`~`/`..` 都归一），抽到共享模块后 safety 与 instructions 共用 |
| 读后写检查时机 | 检查在守卫（写之前），台账记录在 `read` 成功后 | 守卫没法改参数，所以不自动注入 `expected_version`；改为「检查 + 拒绝」语义 |
| 读后写 TOCTOU | 接受「检查到写入」之间的窗口，文档声明 | 窗口是毫秒级；模型若显式传 `expected_version`，工具自身的版本守卫仍兜底 |
| 会话恢复 | 新进程/切会话后台账为空，首次修改需重新 `read` | 会话事件里没有 `version`，无法可靠重建；安全优先，拒绝文案带明确指引 |
| 重复熔断 | 连续相同 `(tool, 排序后参数)`；3 次告警、5 次拒绝 | 阈值可配；遇到不同调用立即清零，避免误伤轮询 |
| 重复熔断的「停轮」 | 不做（nava 侧无法结束 turn） | 需要父包 `AgentLoop` 支持 `stopTurn`，列为后续项；先以「拒绝 + 指引」止血 |
| 敏感文件阻断 | 私钥/云凭据**硬拒**；`.env` **读保持 ask、写默认硬拒** | 调研是 `.env` 全硬阻断；nava 与 OpenCode 对齐已有 ask 语义，写侧当前无任何闸门，先补写侧 |
| 配置缺省 | 三项默认开启 | 与调研「默认安全」一致；提供显式关闭开关，避免用户被卡死 |
| 子代理 | 继承同一份护栏与台账 | `copyPipelineTo` 复制守卫闭包；会话级共享符合「本会话读过」语义 |

## 3. 架构与数据流

```
ctx.tools.call(call)
  ├─ 参数校验
  ├─ guards（注册顺序）
  │   ├─ SensitivePathGuard     ← 命中私钥/凭据/.env 写入 → TOOL_DENIED
  │   ├─ ReadBeforeWriteGuard   ← 覆盖已有文件但未读/已过期 → TOOL_DENIED
  │   └─ RepeatCallGuard        ← 连续第 N 次相同调用 → TOOL_DENIED（N≥denyAt）
  ├─ middlewares
  │   ├─ 权限 / 审批（已有）
  │   ├─ RepeatWarning（新）     ← 执行后按计数追加告警文本
  │   ├─ ReadLedgerMiddleware（新）← read 成功登记 / 写成功刷新
  │   └─ 既有 hooks / lint / story / evict …
  └─ 执行体
```

装配位置：`provideTools(app)` 之后、`instrumentPermission(app)` 之前
（`packages/conatus_code/lib/src/tui/tui_app.dart` 当前 331 / 377 行附近）。
守卫顺序本身不依赖间隔顺序，但放在权限之前便于阅读「安全闸门先于审批」。

会话生命周期：`TuiController` 切换会话的两处赋值
（`tui_controller.dart` 中 `_session = session` / `_session = null`）调用
`safety.resetSession()`，清空台账与重复计数。headless 一个进程一个会话，无需处理。

## 4. 读后写守卫

### 4.1 数据模型

`ReadLedger`（新文件 `lib/src/safety/read_ledger.dart`）：

```dart
class ReadLedger {
  final Map<String, String> _fingerprints = <String, String>{};

  /// canonical 绝对路径 → 本次读取时的文件指纹。
  String? fingerprintOf(String canonical);

  void noteRead(String canonical, String fingerprint);
  void noteWrite(String canonical, String fingerprint);
  void forget(String canonical);
  void clear();
  int get size;
}
```

指纹不复用 `FsInfo.version` 的内部格式，而是用同一套元组自行计算：

```
changed.microsecondsSinceEpoch : modified.microsecondsSinceEpoch : size
```

理由：`FsInfo.version` 由 `dart:io FileStat` 派生（`fs_local_paths.dart`），但
守卫是同步路径，拿不到 `FileSystem.stat`；自行 `FileStat.statSync` 后按相同元组
计算，读侧/写侧都走同一个函数，不依赖父包内部格式。

### 4.2 记录：ReadLedgerMiddleware（中间件）

- 仅对 `name == 'read'` 且 `result.isError == false` 生效。
- 从 `result.value` 取 `path` 与 `version`：**没有 `version` 就不登记**
  （目录列举、图片、PDF 的 value 无 version，本就不能作为文本覆盖的依据）。
- 把 `path` 归一成 canonical（见 §4.4）后，`noteRead(canonical, fingerprint)`。
- 记录失败（stat 抛异常）只吞掉，绝不影响读结果。

### 4.3 检查：ReadBeforeWriteGuard（守卫）

对 `name` 属于 `write` / `edit` / `apply_patch` 的调用：

1. 取目标路径集合：
   - `write` / `edit`：`arguments['path']`；
   - `apply_patch`：从补丁文本尽力抽取
     - unified：`+++ b/<path>` / `--- a/<path>` / `diff --git a/x b/x`；
     - OpenCode：`*** Update File: <path>` / `*** Delete File: <path>` /
       `*** Add File: <path>`（Add 视为新建，豁免）。
     抽不到任何路径 → 放行（fail-open，避免未知格式被误杀）。
2. 对每个目标做 canonical 化，`statSync`：
   - 不存在（新建）→ 豁免；
   - 存在但台账无记录 → 拒绝 `未先读取`；
   - 存在且指纹与台账不一致 → 拒绝 `读后已被修改`。
3. 拒绝文案分别带稳定前缀 `WRITE_WITHOUT_READ:` / `WRITE_STALE_READ:`，
   正文给路径与「请先调用 read 再修改」。模型可据此自愈。
4. 全部通过 → `null`（放行）。

### 4.4 路径归一

复用/搬运 `packages/conatus_code/lib/src/instructions/instruction_paths.dart`
的 `resolveInstructionTargetPath(workdir, home, rawPath)`：

- `~` 展开、相对路径按 workdir 拼接、`..` 归一、符号链接按真实目标；
- 目标不存在时解析最近的已存在祖先再拼回（`canonicalizeBestEffort`）。

为保持分层清晰，新建共享模块 `lib/src/paths/canonical_path.dart` 承载
`canonicalToolPath(...)`：`instructions` 与 `safety` 都从它导入，避免
`safety → instructions` 的反向依赖。`instruction_paths.dart` 现有函数改为
薄委托（纯搬迁，行为不变，指令层现有测试兜底）。

### 4.5 写成功后更新台账

写成功时模型已经「看过」新内容（是它自己写的），所以放行后续连续编辑：

- `write` / `edit` 成功 → 重新 `statSync`，`noteWrite(canonical, fingerprint)`；
- `apply_patch` 成功 → 对补丁涉及的每个路径重新 stat 更新；
- 工具失败 → 不改台账。

实现位置：同一条中间件（`ReadLedgerMiddleware`）在 `next()` 之后按调用名分流，
既记录读、也刷新写。

### 4.6 失败语义与边界

| 场景 | 行为 |
| --- | --- |
| 新建文件 | 放行，无需先读 |
| `write` `mode=create` 但文件已存在 | 先按「覆盖」检查（工具随后自己报错） |
| `write` `mode=append` 已有文件 | 需要先读 |
| `read` 只读了部分（大文件截断） | 仍算读过（调研同样如此）；文档说明 |
| `read` 目录 / 图片 / PDF | 不登记，不能作为覆盖文本的依据 |
| 读后压缩把内容挤出上下文 | 台账保留；模型需自行重读才能看到内容（不影响判定） |
| 恢复旧会话 | 台账为空，第一次修改会要求重读（文案说明原因） |
| `bash` 改写文件 | 不经过本守卫（已知盲区，见非目标） |
| 子代理 | 与主代理共享台账（守卫闭包被复制） |

### 4.7 配置

`require_read_before_write = true`（缺省开）。关闭后守卫整体不挂载。

## 5. 重复调用熔断

### 5.1 签名

```
signature = name + '\u0000' + jsonEncode(按键名排序后的 arguments)
```

- `callId` 不参与（每次调用都不同）；
- 参数值先转字符串再排序，避免 `Map` 顺序抖动；
- 超长参数（例如整段 `content`）先截断到 8 KiB 再算签名哈希（FNV-1a 64 位），
  只存哈希，不存原文，避免长会话内存增长。

### 5.2 状态机

`RepeatTracker`：

```
signature: String?  count: int
```

- `check(ToolCall)`（守卫调用，同步）：
  - 签名不同 → 重置为 `(sig, 1)`，返回 `null`；
  - 签名相同 → `count++`；`count >= denyAt` 时返回拒绝文案，否则 `null`。
- 不同调用一到就清零，天然把「读 → 编辑 → 再读」这类合法序列排除在外。

### 5.3 两段式行为

- **告警（第 `warnAt` 次起，缺省 3）**：守卫放行，`RepeatWarning` 中间件在结果
  后追加（计数 `>= warnAt` 且尚未达到 `denyAt` 时）：
  `\n\n[repeat-breaker] 这是连续第 3 次完全相同的调用；请换方法或汇报结论。`
  失败结果同样附加，但保留 `isError`（不把失败伪装成成功）。
- **拒绝（第 `denyAt` 次，缺省 5）**：不执行，返回
  `REPEAT_CALL_BLOCKED`（`TOOL_DENIED` 体系），正文含工具名、次数与建议
  （改用 `bash` 组合命令 / 先读结果再决定 / 直接汇报）。
- 拒绝后计数不再增长（守卫仍走同一分支），每次相同调用继续被拒；换调用即恢复。

### 5.4 配置

```
repeat_warn_at = 3   # 0 关闭告警
repeat_deny_at = 5   # 0 关闭拒绝
```

两者都为 0 时不挂载。`denyAt <= warnAt` 视为非法配置，解析时报错（fail-fast）。

### 5.5 已知边界

- 有意轮询（`bash` 里 `sleep 2; ls`）会在第 5 次被拒。缓解：`[safety]`
  的 `repeat_exempt_tools = ["bash"]` 可豁免；或提示模型改用后台任务。
- 无法结束 turn：拒绝后模型仍可能继续尝试。后续在父包 `AgentLoop` 读
  `ToolResult.meta['stopTurn']` 才能真正收口（§12）。

## 6. 敏感文件硬阻断

### 6.1 规则表（纯函数，`sensitive_paths.dart`）

按调研 16 篇的清单本地化：

| 类别 | 规则 | 比对 |
| --- | --- | --- |
| `.env` 族 | `.env`、`.env.*` | basename，大小写不敏感 |
| `.env` 豁免 | `.env.example` / `.env.sample` / `.env.template` | 放行 |
| 私钥 | `id_rsa`、`id_dsa`、`id_ecdsa`、`id_ed25519` | 精确名或 `-` / `_` / `.` 变体（`id_rsa-*`、`id_rsa.bak`、`id_rsa_old`） |
| 公钥豁免 | `*.pub` | 放行 |
| 凭据文件 | `credentials` | basename（任意目录） |
| 云凭据 | `.aws/credentials`、`.gcp/credentials` | 路径后缀（段级） |
| 用户追加 | `[safety] extra_sensitive_paths` | 段级前缀或精确名（实现时二选一并写进 README） |

判定顺序：豁免 → 路径后缀 → 精确名 → 变体 → `.env` 族。返回命中的类别，
供文案说明「为什么被挡」。

### 6.2 作用面

`SensitivePathGuard`（守卫）对所有工具生效：

1. 从注册表拿到 `Tool.pathParams`，取所有声明为路径的参数（`read` /
   `write` / `edit` / `list` / `glob` / `grep` / `lsp_*` 等）；
2. `bash` 额外做字面扫描：按引号与空白切分，任一 token（去 `~` 展开后）
   命中规则即拒绝。覆盖 `cat ~/.ssh/id_rsa`、`cp x ~/.aws/credentials`、
   `> credentials` 等；变量拼接/`sh -c` 不保证（文档注明）；
3. `apply_patch`：扫描补丁里出现的路径行；
4. 命中 → `TOOL_DENIED`，消息以 `SENSITIVE_PATH:` 开头并带路径与被挡类别。

已知盲区：对目录型参数（如 `grep path: "~/.ssh"`）只校验目录本身，不阻止
`grep` 命中目录内敏感文件的内容；`rg` 自身会跳过隐藏目录，但用户显式指定
`-uu` 时仍可能读到。这与「bash 可绕过」同属字面路径闸门的边界，文档写明。

### 6.3 `.env` 的读/写区分

- **读**：保持 `conatus_agent` 的默认 `ask`（`.env.example` 放行）；
- **写**（`write` / `edit` / `apply_patch` / `bash` 字面重定向）：
  缺省硬拒（`deny_dotenv_writes = true`）。理由：当前 `ask_when_needed` 下
  写是 medium 且阈值 high，实际不询问即可覆盖，属于缺口。

> 这是相对现状的**行为变更**，会在 README 与 CHANGELOG 明确写出，并提供
> `deny_dotenv_writes = false` 的逃生口。

### 6.4 配置

```
[safety]
protect_private_keys = true     # 私钥 / 凭据硬拒
deny_dotenv_writes = true       # .env 族写入硬拒
extra_sensitive_paths = []      # 追加路径/名称
```

关闭 `protect_private_keys` 后只保留既有 `.env` 读 ask，不做任何硬拒。

## 7. 配置汇总

新增 `[safety]` 表（`config_schema.dart` + `config_parser.dart` + 配置模板）：

```toml
[safety]
require_read_before_write = true   # 读后写守卫
repeat_warn_at = 3                 # 0 = 关闭告警
repeat_deny_at = 5                 # 0 = 关闭拒绝
repeat_exempt_tools = []           # 例如 ["bash"]
protect_private_keys = true
deny_dotenv_writes = true
extra_sensitive_paths = []
```

解析约束：

- 阈值必须 `>= 0`；`denyAt` 与 `warnAt` 同时非 0 时须 `denyAt > warnAt`；
- 未知字段保持现有策略（nava 当前对未知键宽松，按既有 `ConfigValues` 行为）；
- 模板写入 `config_loader` 的首次生成文件，并在 README「配置」一节补一段。

## 8. 文件与代码组织

| 文件 | 职责 | 预估行数 |
| --- | --- | --- |
| `lib/src/paths/canonical_path.dart` | 路径归一（共享模块，指令层薄委托） | ~60 |
| `lib/src/safety/read_ledger.dart` | 台账 + 记录/刷新中间件 | ~120 |
| `lib/src/safety/write_guard.dart` | 读后写守卫 + 补丁路径抽取 | ~140 |
| `lib/src/safety/repeat_breaker.dart` | 签名、状态机、守卫 + 告警中间件 | ~110 |
| `lib/src/safety/sensitive_paths.dart` | 纯规则匹配 | ~120 |
| `lib/src/safety/sensitive_guard.dart` | 工具参数/bash/补丁适配 | ~110 |
| `lib/src/safety/safety_assembly.dart` | `provideToolSafety(...)`、服务键 `'toolSafety'` | ~80 |
| `lib/safety.dart` | 包内导出（与 `lib/fs_tools.dart` 等并列） | ~10 |

均满足仓库硬约束（单文件 ≤ 200 行、函数 ≤ 40 行、分支 ≤ 3）。
装配与复位改动点：

- `lib/src/tui/tui_app.dart`：在 `provideTools` 后调用 `provideToolSafety`；
- `lib/src/tui/tui_controller.dart`：两处 `_session` 赋值后 `toolSafety.resetSession()`；
- `lib/src/config/config_schema.dart` / `config_parser.dart` / 模板 / README / CHANGELOG。

## 9. 测试矩阵

新目录 `packages/conatus_code/test/safety/`，全部用手写 Fake（仓库不用 mock 框架）。

### 9.1 读后写

| 用例 | 期望 |
| --- | --- |
| 新建文件直接 `write` | 放行 |
| 覆盖已有文件未读 | 拒绝，文案含 `WRITE_WITHOUT_READ` |
| `read` 后 `write` | 放行 |
| `read` → 外部改文件 → `write` | 拒绝，文案含 `WRITE_STALE_READ` |
| `read` → 自己 `write` → 再 `edit` | 放行（写成功刷新台账） |
| `read` 目录 / 图片（value 无 version）后覆盖同名 `.txt` | 仍算未读 |
| `resolve` 出符号链接别名 | 读写两侧命中同一键 |
| `apply_patch` 修改未读文件 | 拒绝；`*** Add File` 放行 |
| 切换会话后再写 | 拒绝（台账已清） |
| `require_read_before_write = false` | 全部放行 |

### 9.2 重复熔断

| 用例 | 期望 |
| --- | --- |
| 连续 2 次相同 | 正常执行，无告警 |
| 第 3 次相同 | 执行并附 `[repeat-breaker]` |
| 第 5 次相同 | 不执行，`TOOL_DENIED`，含 `REPEAT_CALL_BLOCKED` |
| 中间插入不同调用 | 计数清零 |
| 参数键顺序不同但语义相同 | 视为同一签名 |
| `repeat_exempt_tools = ["bash"]` | bash 不计数 |
| 配置 `denyAt <= warnAt` | 解析报错 |

### 9.3 敏感文件

| 用例 | 期望 |
| --- | --- |
| `read ~/.ssh/id_rsa` | 拒绝 |
| `read ~/.ssh/id_rsa.pub` | 放行 |
| `read .env` | 仍走权限 ask（不被守卫拦截） |
| `read .env.example` | 放行 |
| `write .env` | 拒绝（缺省） |
| `write .env` 且 `deny_dotenv_writes = false` | 放行到权限层 |
| `read .aws/credentials` | 拒绝 |
| `bash cat ~/.ssh/id_ed25519` | 拒绝 |
| `bash echo $KEY > /tmp/x` | 放行（不误伤） |
| `apply_patch` 补丁含 `credentials` | 拒绝 |
| `extra_sensitive_paths = ["secrets"]` | `secrets/token.txt` 拒绝 |
| 子代理调用 | 同样被拒（守卫被复制） |

### 9.4 装配与回归

- 三项全关 → 现有工具测试全绿（行为零变化）；
- 与 story review / 审批同时开启：守卫拒绝时**不弹审批窗**（守卫早于中间件）；
- headless 路径同样生效；
- `dart analyze --fatal-infos` 无新增告警。

## 10. 交付步骤

1. **P0 路径工具**：抽 `canonicalToolPath`，指令层改调用，跑指令层测试。
2. **P1 读后写**：`ReadLedger` + 记录中间件 + 守卫 + 配置 + 测试。
3. **P2 重复熔断**：`RepeatTracker` + 守卫 + 告警中间件 + 配置 + 测试。
4. **P3 敏感文件**：规则表 + 守卫 + 配置 + 测试。
5. **P4 接线与文档**：`provideToolSafety` 装配、会话复位、README / CHANGELOG、
   `/doctor` 是否需要展示（可选）。
6. **P5 验证与交付**：
   ```bash
   cd packages/conatus_code
   dart analyze --fatal-infos
   dart test
   bash tool/build_binary.sh      # dist/nava
   ```
   提交规范：`feat(safety): 读后写守卫与重复调用熔断`、
   `feat(safety): 敏感文件硬阻断`；随后父仓库同步 gitlink
   `chore(code): 同步子模块 gitlink（工具层安全护栏）`。
   若父仓库 conatus 有推送，按 `tool/pin_conatus_refs.sh` 刷新子模块 ref。

预估：P1 ≈ 1 天，P2 ≈ 0.5 天，P3 ≈ 1 天，P0/P4/P5 ≈ 1 天，合计 3–4 天。

## 11. 风险与回滚

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 读后写误拒（路径拼写/符号链接） | 模型反复重读，体验下降 | canonical 归一 + 「先 read」文案直接可执行；保留配置开关 |
| 恢复会话后台账为空 | 首次修改被拒 | 文案说明「本会话尚未读取，请先 read」；必要时后续从会话事件重建 |
| 重复熔断误伤轮询 | 合法命令被拒 | 阈值可配 + `repeat_exempt_tools`；后台任务优先 |
| `.env` 写入硬拒影响既有工作流 | 用户被挡 | `deny_dotenv_writes = false`；CHANGELOG 醒目标注 |
| 守卫同步 statSync 拖慢调用 | 每次写多一次 stat | 仅写类工具触发；单次 stat 微秒级 |
| 检查与写入之间的竞态 | 极小概率漏检 | 文档声明；模型传 `expected_version` 时仍由工具版本守卫兜底 |
| 配置项扩散 | 维护成本 | 全部集中在 `[safety]` 一节，缺省即推荐值 |

回滚：三项各自独立，删除对应 `provideToolSafety` 的挂载即恢复旧行为；
配置全关可作为运行时快速回滚。

## 12. 后续项（本次不做）

| 项 | 调研来源 | 价值 | 前置 |
| --- | --- | --- | --- |
| `select_tools` 动态工具披露 | 10 | 长会话/多 MCP 每步省数千至数万 token | 工具注册支持 `deferred`；系统提示公告；权限规则按名仍可匹配 |
| 访问感知的工具并行调度 | 05 / 08 | 一轮多工具时延显著下降 | 父包 `AgentLoop` 与 `Tool` 增加 `accesses` 声明 |
| `ToolResult.meta['stopTurn']` | 08 / 05 | 重复熔断/预算耗尽能真正收口 | 父包 `AgentLoop` 读 meta 并结束 turn |
| Hooks 事件扩展（SessionStart / UserPromptSubmit / PostToolUseFailure / PreCompact…） | 17 | 生态与审计能力 | 现有 3 事件机制扩展 + 配置 |
| manual 模式 git 工作区内写自动放行 | 14 | 减少无意义审批 | 检查点可用性判定（nava 已有 checkpoint） |

### 观察项（不在本次范围）

`lib/src/story/story_review.dart` 的注释称「最后注册者最外层」，但
`ToolRegistry._chain` 的实现与 `tools_test.dart` 的用例表明**先注册者最外层**。
本次护栏走守卫阶段，不受该顺序影响；该注释与实际的挂载顺序不一致，建议单独
核对（可能是注释写反，也可能是 story 门的挂载顺序与预期相反），不要顺手改。

## 13. 验收清单

- [ ] 新建文件无需先读；覆盖未读/过期文件被拒且文案可执行
- [ ] 连续第 3 次相同调用告警、第 5 次拒绝；不同调用清零
- [ ] 私钥/云凭据/`.env` 写入按决策硬拒；`.pub` 与 `.env.example` 放行
- [ ] 三项均可用 `[safety]` 独立关闭，关闭后零行为变化
- [ ] 子代理、headless 路径同样生效
- [ ] 守卫拒绝时不触发审批弹窗
- [ ] `dart analyze --fatal-infos` + `dart test` + `dist/nava` 构建通过
- [ ] README 配置章节与 CHANGELOG 已更新
