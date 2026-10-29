# OpenSandbox 与 nava 沙箱的适配评估

> 评估对象：[opensandbox-group/OpenSandbox](https://github.com/opensandbox-group/OpenSandbox)
> （AAIF 项目，Apache-2.0，`Secure, Fast, and Extensible Sandbox runtime for AI agents`）。
> 评估基准：`packages/conatus_code` 当前的两层沙箱实现（README「沙箱」节，约 970 行起）。

## 1. 结论

**能用，但不是「换一层后端」那么用。**

| 用法 | 可行性 | 代价 | 判断 |
|------|--------|------|------|
| A. 把 **nava 整体跑进** OpenSandbox 沙箱（镜像 + 工作区卷） | 高 | 零代码，仅镜像与运维 | ✅ 首选，先做 |
| B. 本地 nava + **远端 shell**（execd `/command` 代替 `sandbox-exec`/`bwrap`） | 中 | 新增 HTTP+SSE 执行器（约 400–600 行）+ 配置 + 生命周期管理 | ⚠️ 条件成立才做 |
| C. 通过 **opensandbox-mcp** 把沙箱能力暴露成工具 | 高 | 零代码 | ⚠️ 只适合演示，不解决隔离 |

核心判断依据：**OpenSandbox 是「环境级」沙箱（容器/微VM + 服务端），nava 现有 Layer 2 是「进程级」护栏（同一台机器上一行命令的外壳）。** 两者不是同一抽象层，A 是顺理成章的用法，B 是把环境级沙箱硬塞进进程级接缝——技术上完全可行（接缝本来就是为此设计的），但只有在「必须让命令在远端执行」时才值得。

B 能否成立，取决于一个硬前提：

> **沙箱里的工作区必须和 nava 本地看到的是同一份字节，且绝对路径一致**（host bind mount 到相同路径）。

否则会 split-brain：文件工具、formatter、LSP、checkpoint/rewind、diff、会话日志都在本地跑，只有 shell 在远端跑，两边看到的文件不同——这不是「沙箱」，是「两个工作区」。

## 2. OpenSandbox 关键契约（决定适配成本的部分）

| 维度 | 事实 | 出处 |
|------|------|------|
| 形态 | `opensandbox-server`（Python，`uvx opensandbox-server`）+ Docker（本地）或 Kubernetes（集群）；**SDK 只有 Python / Java / Kotlin / TS / C# / Go，无 Dart** | README「Getting Started」「SDKs」 |
| 生命周期 API | `http://localhost:8080/v1`，头部 `OPEN-SANDBOX-API-KEY`；`POST /sandboxes` 创建、`DELETE /sandboxes/{id}`、`pause`/`resume`、`renew-expiration`、`GET /sandboxes/{id}/endpoints/{port}` 拿执行端点 | `specs/sandbox-lifecycle.yml`、`docs/api/index.md` |
| 执行 API | execd，默认 `:44772`，头部 `X-EXECD-ACCESS-TOKEN`；`POST /command`（SSE 流式，stdout/stderr/status/`execution_complete` 带 `exit_code`）、`DELETE /command` 中断、`background` 模式 + `/command/status/{id}` + `/command/{id}/logs` 增量日志、`timeout` 毫秒、`envs`、`cwd`、`argv`（免 shell 解析） | `specs/execd-api.yaml` 409–585 行、`docs/architecture/data-plane/execd.md` |
| 文件 API | 完整：`/files/upload`（multipart，暂存后 rename，失败不截断原文件）、`/files/download`（支持 Range）、`/directories/list`、`/files/mv`、`/files/search`、`/files/replace`、`/files/permissions`，另有 `/v1/filesystem/{uid}/{gid}/...` 身份化路由 | 同上 |
| 交互 | `/session` 有状态 bash 会话（跨调用保留 cwd/env）；`/pty` 真终端（WebSocket，支持只读旁观） | 同上 |
| 工作区 | `volumes[].host` 支持 **host path bind mount**（`mountPath`/`readOnly`/`subPath`），`pvc` 走 K8s PVC / Docker named volume | `specs/sandbox-lifecycle.yml` `Volume` schema |
| 网络 | 每沙箱**出站**策略（`/sandboxes/{id}/networkpolicy` + 沙箱内 egress sidecar），入站经统一网关 | `specs/egress-api.yaml` |
| 其它 | 快照（`/sandboxes/{id}/snapshots`）、pause/resume 保留内存与磁盘（Firecracker）、Credential Vault（代理外部凭据，真 key 不进沙箱）、MCP server、`osb` CLI | README「Features」 |
| 隔离强度 | runc / gVisor / Kata / Firecracker 可选；execd 另有一层 launcher（丢 capability、`no_new_privs`、syscall denylist、Landlock 写限制）+ 可选 isolated session（bubblewrap） | `docs/architecture/data-plane/execd.md`「Layered security」 |

对比 nava 现状：Seatbelt / bwrap 是**同机进程级**护栏，写面靠 profile 授权，网络靠 `(deny network*)` / `--unshare-all`；OpenSandbox 是**内核边界**（容器/微VM）+ 服务端编排。后者安全模型明显更强（尤其 Linux 上不受 userns 限制之苦，还支持 Windows 沙箱），但要求 Docker/集群在场。

## 3. nava 侧接入点（干净，不用改架构）

- 接缝：`conatus_foundation` 的 `ShellExecutor`（`lib/src/shell.dart:177`）与 `FileSystem`（`fs.dart:21`）都是抽象契约，`shell.dart:5` 的注释明确写了「沙箱执行器、远程执行器或 PowerShell 执行器都能替换默认实现」，`fs.dart:47` 也预留了「远程/内存 fs 可按需覆盖 `readBytes`」。
- 装配点唯一：`bin/conatus_code.dart:141-166`——`probeSandboxBackend()` 探测 → `resolveSandboxLayers(...)` 产出 `SandboxLayers{fs, shell}` → 注入 `ConatusTuiRuntime.create`。
- 现状后端是枚举 `SandboxBackendKind{seatbelt, bubblewrap}`（`sandbox_probe.dart:8`），`SandboxedShellExecutor` 内部直接 `Process.start(sandbox-exec|bwrap, ...)`（`sandboxed_shell.dart:150`）。**远端执行器应是一个新的 `ShellExecutor` 实现，而不是往这个枚举里加值**——`_spawn` 的前提（本机进程）在远端不成立。
- 命令策略（`CommandPolicy`：deny / review / allow）与文件 jail（`JailedFileSystem`）可以完整保留，与执行位置无关，这是 B 方案最省事的部分。

## 4. 三种接法对比

### A. nava 跑在沙箱内

镜像里放 nava 二进制 + 运行时（dart/node/git 等），`volumes[].host` 把用户仓库挂到同一路径，`entrypoint` 直接 `nava`。

- 优点：零代码；隔离由内核边界提供；一个镜像搞定「云端/多租户/CI」场景；`/rewind`、LSP、formatter、git 全都在沙箱内自洽；Windows 也能覆盖（nava 本地 Layer 2 在 Windows 是禁用的）。
- 代价：沙箱内要能访问模型 API（egress policy 放行，或走 Credential Vault 不落真 key）；nava 的 TUI 要在容器里跑（PTY 已支持）；本地开发用户得先起 server + Docker，体验门槛陡增。
- 结论：这是 OpenSandbox 的**本命用法**，官方就有 Claude Code / Codex CLI 的同类 example。

### B. 本地 nava + 远端 shell

新增 `OpenSandboxShellExecutor implements ShellExecutor`：

| 契约点 | 映射 | 成本 |
|--------|------|------|
| `run` | `POST /command`（SSE）→ 累积 stdout/stderr → `execution_complete.exit_code` | 中（SSE 解析 + 分帧） |
| 超时 | 请求体 `timeout` + 本地 `Timer` 双保险，`timedOut` 自行标记 | 低 |
| 取消 | `cancelSignal` → `DELETE /command` | 低 |
| `start` | `background: true` → `GET /command/{id}/logs` 轮询 → `ShellProcess.readOutput` 增量投递 | 中 |
| `kill` | `DELETE /command` | 低 |
| `stdin` | 一次性 stdin 需 `/session` + `run`（合并流，无独立 stderr）或 PTY；`ShellExecRequest.stdin` 的语义会退化 | 中，且有语义差 |
| 网络白名单 | execd 无「按命令」网络开关 → 退化为沙箱级 egress 策略（粗粒度） | 中，能力下降 |
| 环境 | `envs` 直接映射；`defaultMinimalEnv` 语义保留在客户端 | 低 |
| 端点 | `GET /sandboxes/{id}/endpoints/44772` 取 URL + 必需头部，注意 `X-EXECD-ACCESS-TOKEN` | 低 |
| 生命周期 | 起会话时 `POST /sandboxes`（带 `timeout`），退出 `DELETE`；崩溃靠 expiration 兜底 | 中 |

**只有当工作区同路径 bind mount 时**，`FileSystem` 才可以继续用本地实现（Layer 1 jail 不变）。要支持 K8s / 远端主机，则必须再实现一个走 execd `/files` 的远程 `FileSystem`（`resolve`/`stat`/`lstat`/`listDir`/`readText`/`readBytes`/`writeText`（原子写 + 版本守卫）/`editText`/`remove`/`contains`/`processPath`），工作量是 shell 侧的 2–3 倍，且 `processPath`（「子进程可打开的路径」）在远端是**不可满足**的语义——本地 formatter/LSP/git 会直接失效。

### C. MCP 接入

`opensandbox-mcp`（stdio/http）提供 `sandbox_create` / `command_run` / `file_*` 等工具，nava 已有 MCP 客户端。

- 优点：今天就能演示，零代码。
- 缺点：模型拿到的是「又一个能跑命令的地方」，与 nava 自己的 shell/文件工具并存，工作区不同步；不在审批链的语义里（MCP 未声明风险按 `high` 进审批，这倒是对的）。**不构成隔离方案**。

## 5. 不匹配点清单（按影响排序）

1. **分发形态冲突（最硬）**：nava 的卖点是单二进制、纯 Dart、零外部依赖；B 方案要求用户装 Python + Docker 并常驻一个 server。这对「本地日常编码」是净损失，对「云端/CI/多租户」是净收益。
2. **工作区一致性**（见 §1 硬前提）：只有 host bind mount 同路径才不 split-brain；跨主机即需要远程 FS，而 `processPath` 语义在远端不成立。
3. **粒度反转**：nava 现在是「逐命令」网络开关 + 「逐路径」可写白名单；OpenSandbox 是「逐沙箱」egress 策略 + volume 挂载权限。前者精细、后者强。迁移后 `network_allowlist`（按命令前缀放行）失去对应物。
4. **stdin / 交互语义**：`ShellExecRequest.stdin` 是一次性写入；execd 的一次性命令没有 stdin 通道，只能退到 `/session`（stderr 合流）或 PTY。实际使用面很小（工具层基本不用 stdin），但契约会变形，需要在文档里写清。
5. **输出上限**：nava 在客户端截断（`maxOutputBytes`，溢出落 spill 文件）；SSE 方案同样在客户端截断，语义可保持，但 spill 文件落在本地而内容来自远端——需明确 spill 只做摘要。
6. **生命周期泄漏**：nava 异常退出会留下沙箱。必须有 `timeout` + 启动时按 metadata 清理孤儿沙箱（`GET /sandboxes` 过滤）。
7. **无 Dart SDK**：需自写 REST 客户端，但只用到 3 组端点（lifecycle / command / files），spec 是 OpenAPI，可代码生成，风险低。
8. **延迟**：每命令一次 HTTP + SSE，本地 Docker 约几毫秒到几十毫秒；远端集群则每个命令都吃 RTT，`rg`/`git status` 类高频小命令体感会变差（这也是 A 方案更优的原因之一）。

## 6. 建议路线

**P0（半天，零代码）· 可行性验证**

```bash
uvx opensandbox-server init-config ~/.sandbox.toml --example docker && uvx opensandbox-server
osb sandbox create --image alpine --timeout 30m -o json
osb command run <id> -o raw -- sh -c 'echo hi; echo err >&2; exit 3'
```

验证四件事：① SSE 的 stdout/stderr 分帧与 `exit_code` 行为；② `DELETE /command` 中断延迟；③ host bind mount 到同路径后，本地写、沙箱读是否即时可见；④ `background` + `/command/{id}/logs` 的增量语义能否满足 `ShellProcess.readOutput`。

**P1（1–2 天）· A 方案落地**：写 Dockerfile（nava + 运行时），`volumes[].host` 挂工作区，`entrypoint` 跑 nava，headless 模式先用（`validateHeadlessSafety` 此时可显式 `--allow-unsafe-headless`，因为隔离已由沙箱提供——注意这需要产品语义上的说明，不能只是绕闸门）。

**P2（条件触发）· B 方案**：仅当出现「nava 必须在本机跑、命令必须在远端跑」的真实需求（例如企业要求代码不出内网机器）才做。顺序：`OpenSandboxShellExecutor` + 配置段 `[sandbox.opensandbox]`（domain / api_key / image / volume / timeout）→ 端点解析与 token 透传 → 生命周期与孤儿清理 → 测试用本地假 execd（SSE fixture）覆盖。**不要先做远程 FileSystem**。

## 7. 部署形态核查（决定结论的关键）

| 问题 | 事实 |
|------|------|
| 有 JS/TS 版的 server 吗？ | 没有。`sdks/sandbox/javascript` 是纯 HTTP 客户端；server 只有 Python（FastAPI）；`components/*` 是 Go |
| 宿主必须装 Python 吗？ | 不必。官方镜像 `opensandbox/server:release-1.1.0` + `server/docker-compose.example.yaml`（挂 `/var/run/docker.sock`）即可，宿主只需容器运行时 |
| 宿主必须装 Go 吗？ | 不必。execd（`go 1.25.0`）、egress、ingress 都是预编译镜像，按 `[runtime].execd_image` 注入 |
| 能不能用 Bun 打包 + Dart FFI 调？ | `bun build --compile` 产出的是可执行文件，不是 C ABI 共享库，`dart:ffi` 打不开；且它只是 HTTP 客户端，换不来隔离 |
| Go 能编成 C ABI 给 FFI 吗？ | 能（`-buildmode=c-shared`），但同样只是客户端，且引入跨平台交叉编译负担，收益低于直接写 Dart REST 客户端 |
| 能不用容器吗？ | **不能。** `[runtime].type` 只有 `docker` / `kubernetes`；Fast Sandbox 需 Linux + KVM；ROADMAP 无 containerless 运行时。execd 可裸跑，但其加固层（`components/execd/native/launcher.c`：Landlock / seccomp / `no_new_privs`）仅 Linux 有效，macOS 上等于零隔离，且还需自建生命周期管理 |

## 8. 决策记录（2026-10-29）

**不引入容器运行时 → OpenSandbox 不适用，P0 取消。**

理由：OpenSandbox 是**平台**而非库，其隔离边界由容器/微VM 提供；去掉 Docker/K8s 之后剩下的只有 execd 这个 HTTP 执行 daemon，隔离、生命周期、跨主机能力全部消失，等于自建一个更弱的 `SandboxedShellExecutor`。

在「不加容器依赖」约束下，可选的隔离路线：

| 目标 | 方案 | 代价 |
|------|------|------|
| 本机加固（当前需求） | 维持 Seatbelt / bwrap 两层现状 | 零新增依赖 |
| Linux 上不依赖 userns | **Landlock + seccomp**（纯 syscall，经 Dart FFI 调用；execd 的 `launcher.c` 即此做法） | 中：需写 FFI 绑定与规则集构建 |
| 命令跑在别处 | 远端 SSH / 开发机执行器（`ShellExecutor` 接缝） | 中：无需容器 |
| 不受信任代码执行（非 shell） | Wasm（wasmtime/wamr，FFI）或 JS isolate | 中：跑不了 git / dart 工具链 |
| 内核级多租户隔离 | 必须有运行时（Docker / gVisor / Kata / Firecracker） | 高：即 OpenSandbox 路径 |

结论：nava 现有两层沙箱已经是「无容器」约束下的正解；要再提升，方向是 Linux 上的 Landlock（补 userns 不可用的场景），而不是引入 OpenSandbox。
