# 调研：conatus 拓展 Go 版本的工作量评估

## 一、现状盘点（实测数据）

### 代码规模（`lib/` 实现代码，不含子模块）

| 层级 | 包 | 文件数 | 行数 |
|------|----|--------|------|
| 核心底座 | conatus_core | 5 | **511** |
| 稳定包 ×13 | foundation / llm / agent / cron / schedule / skill / mcp / intent? 等 | ~190 | **~27,500** |
| 实验包 ×9 | ontology / workflow / team / intent / asr / tts / doc 等 | ~140 | **~14,000** |
| **合计（伞包 24 包）** | | **~340** | **~42,000** |

测试代码另有 **~45,000 行**（不含子模块），与实现代码比例接近 1:1 —— 这是本项目质量基线，Go 版若要对等，测试不能省。

子模块（独立产品，通常不在移植范围）：conatus_code 20.3k 行、cowriter 20.7k 行。

### 分层依赖（无环，自上而下）

```
core (511行)  ← 零依赖，范式本体：Context / EffectScope / Reactor / redaction
  ↑ foundation (5.1k)：timer/logger/tools/shell/fs/session/memory/database/system-prompt
  ↑ credentials / llm / search / skill / asr / tts / mcp / schedule / cron / compaction
  ↑ agent (7.1k)：Agent Loop / plan / sub-agent / reflection / eval / approval / recovery
  ↑ tasks / alerting / browser_use / computer_use / doc / intent / observability / team / workflow / ontology
```

## 二、Dart → Go 的映射难度分析

### 容易映射（约占 70% 工作量，直译型）

- **conatus_core**：511 行但语义密度最高。LIFO 撤销栈、脏标记+重跑的 Reactor、上下文树服务查找 —— 都是命令式逻辑，Go 用 `sync.Mutex` + 接口即可表达。**难点不在行数在语义保真**：现有 1513 行测试含随机顺序（3 种子）+ 覆盖率 + 7 个变异注入的 fail-closed 验证，Go 版要重建同等验证强度。
- HTTP 类（llm / credentials / mcp / search）：`http` 包 → `net/http`，SSE 流式 → bufio 逐行读，Go 生态成熟。
- shell / fs 能力缝：`bash -c` 与原子写入，Go `os/exec` + `os.Rename` 直接对应。
- cron / schedule：定时器逻辑，Go `time.Timer` + `time/tzdata` 替代 `timezone` 包。

### 需要重新设计（真正的成本所在）

1. **异步模型**：全仓 499 处 `Stream` / `StreamController` 用法（199 个文件）。Dart 单线程事件循环 + `await` 顺序语义 → Go 要决定：全部改阻塞式同步调用（最简单，丢失背压控制），还是 channel + goroutine（引入 goroutine 生命周期管理、泄漏风险、取消传播 —— 需要一整套 `context.Context` 约定）。**这一个决策影响所有包的 API 形态**。
2. **类型擦除的服务树**：Dart 用 `Map<String, Object?>` + 泛型 `ctx.service<T>()`，Go 泛型（1.18+）能表达但服务注册/查找会变成 `Service[T]` 类型注册表或退回 `any` + 类型断言，API  ergonomics 会差一截。
3. **Tool 系统的 ParamSpec → JSON Schema 投影**：Dart 手写声明式参数；Go 惯例是用 struct tag + 反射生成，等于重做一套工具声明 DSL。
4. **EffectScope 的泛型撤销函数**：`Disposer` 闭包 + LIFO，Go 表达没问题，但 Dart 依赖 GC 不管资源、Go 要显式管 goroutine 取消，错误处理路径（`err error` 显式返回 vs Dart 异常）会改变所有「抗异常」语义的实现方式。
5. **asr / tts**：音频走 ffmpeg 子进程，可平移；但 Dart 侧 WebSocket 流式协议对接要重写。

### 不可移植 / 需替代

- `timezone`（IANA）→ Go `time.LoadLocation` + 内嵌 tzdata（行为略有差异，cron 边界用例要重测）。
- Dart 测试生态（`package:test` 分组/expect）→ Go `testing` + testify，45k 行测试要逐包重写。
- 变异测试脚本 `tool/mutate_reversibility.sh`（sed 注入 7 个 bug）→ 可改写为 Go 版，成本低但要做。

## 三、工作量估算（按范围分档）

以「1 名熟悉双语的工程师 + AI 编码辅助」为基准，验证标准对齐仓库现状（`analyze` 级静态检查 + 对等测试）：

| 档位 | 范围 | 代码量（实现+测试） | 估算工作量 |
|------|------|--------------------|------------|
| **T0 概念验证** | conatus_core 单包 + 可逆性验证套件 | 511 + 1513 行 | **2~3 周** |
| **T1 可用 Agent MVP** | core + foundation + llm + compaction + skill + search + tasks + agent（8 包） | ~17k + ~17k 行 | **3~4 个月** |
| **T2 稳定包全集** | T1 + credentials / mcp / schedule / cron / asr / tts（14 包） | ~28k + ~30k 行 | **5~7 个月** |
| **T3 全量对等** | T2 + 9 个实验包 | ~42k + ~45k 行 | **8~12 个月** |
| 子模块（另计） | conatus_code / cowriter 的 Go 版 | ~41k + ~37k 行 | 各 +2~3 个月 |

估算依据：移植型工作（语义已定型、有测试做规格）在 AI 辅助下约 600~1000 行/人日（含测试与验证）；T0 单独偏高是因为 core 语义密度与验证强度远超其行数。

## 四、关键风险与建议

1. **维护分裂是最大的长期成本**：Go 版一旦存在，Dart 侧每次演进（本项目迭代活跃，实验包 API 还会破坏性变更）都要双写。建议明确 Go 版的定位——是「冻结某个 tag 的一次性移植」还是「长期双轨」。若是后者，实际成本要 ×1.3~1.5。
2. **建议从 T0 开始验证假设**：core 只有 511 行，先花 2~3 周把 Context/EffectScope/Reactor 在 Go 里跑通并复刻变异测试，能暴露 80% 的范式映射风险（异步语义、撤销时序、Reactor 收敛），再决定是否继续。
3. **不建议直译**：Dart 的 `await` 顺序语义+异常模型若机械映射到 goroutine+channel 会制造大量隐性 bug。Go 版应采用「同步调用 + 显式 `context.Context` 取消」的惯用形态，接受 API 形态与 Dart 版不同。
4. 实验包（尤其 ontology / workflow / team）API 未稳定，建议**等其稳定或直接跳过**，移植优先级最低。

## 五、交付方式选项

本调研本身已完成。可选后续动作：

- **A. 仅交付调研结论**：报告如上，不动代码。
- **B. 报告 + T0 spike**：另建仓库/分支，用 Go 实现 conatus_core 并对等复刻可逆性验证（含变异测试），2~3 周量级的实证验证，为后续决策提供实测数据。
