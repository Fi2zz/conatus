# conatus

> 时空可组合性（Spatiotemporal Composability）编程范式的 Dart 实现。
>
> 基于论文 *A Programming Paradigm for Spatiotemporal Composability*
> （arXiv:2608.25512）的核心机制。

本仓库是一个 [pub workspace](https://dart.dev/tools/pub/workspaces) monorepo，按依赖层次拆分为多个包。

## 包结构

| 包 | 说明 | 依赖 |
|----|------|------|
| [`conatus_core`](packages/conatus_core) | 核心范式：`Context` / `EffectScope` / `Reactor`（零运行时依赖） | — |
| [`conatus_foundation`](packages/conatus_foundation) | 基础设施插件：timer / logger / loader / tools / shell / fs / session / system-prompt / memory / database / ask-user | `conatus_core` |
| [`conatus_llm`](packages/conatus_llm) | 大模型接入（豆包 / DeepSeek，chat 与 responses 两种形态） | `conatus_core`、`http` |
| [`conatus_search`](packages/conatus_search) | 搜索能力缝 + `web_search` / `fetch_url` | `conatus_core`、`conatus_foundation`、`http` |
| [`conatus_asr`](packages/conatus_asr) | ASR 能力缝（豆包/火山流式识别）+ `transcribe_audio` + 可替换音频源 | `conatus_core`、`conatus_foundation` |
| [`conatus_agent`](packages/conatus_agent) | Agent Loop 与产品化：plan / sub-agent / reflection / telemetry / eval / approval / skill / recovery | `conatus_core`、`conatus_foundation`、`conatus_llm` |
| [`conatus_tui`](packages/conatus_tui) | 基于 [nocterm](https://pub.dev/packages/nocterm) 的文本 TUI：对话 + 工具闭环、斜杠命令、会话选择面板 | `conatus_agent`、`conatus_llm`、`conatus_search`、`nocterm` |
| [`conatus`](packages/conatus) | 伞包（umbrella）：再导出以上全部，保持 `package:conatus/conatus.dart` 兼容 | 全部 |

依赖方向自上而下，无环：

```
conatus ─▶ conatus_agent ─▶ conatus_llm ─▶ conatus_core
                │                              ▲
                └▶ conatus_foundation ─────────┘
conatus_search ─▶ conatus_foundation
conatus_asr ────▶ conatus_foundation
```

## 快速开始

```dart
import 'package:conatus/conatus.dart'; // 伞包：完整 API
// 也可以按需只引入某个模块：
// import 'package:conatus_core/conatus_core.dart';
// import 'package:conatus_agent/conatus_agent.dart';
```

```bash
dart pub get
```

## 作为依赖使用

各包之间以 `^0.15.0` 的版本约束互相依赖，而 `conatus_*` 包**尚未发布到 pub.dev**，
因此不能只声明一个伞包依赖——pub 会去 pub.dev 找不存在的 `conatus_search` 等而失败。

> 包是纯 Dart（不含 Flutter SDK 依赖），Flutter 项目同样可用，只是用 `flutter pub get`。
> 下面的 `ref` 建议 pin 到 release tag 或 commit SHA，避免 `master` 漂移；
> 目前仓库还没有 tag，可先用 `master`，或自行 `git tag v0.15.0 && git push origin v0.15.0`。

### 方案 A：Git 依赖（当前可用）

把伞包与它的兄弟包都指向同一个仓库；兄弟包放进 `dependency_overrides`，
否则 pub 会按 hosted 源去 pub.dev 查找：

```yaml
dependencies:
  conatus:
    git:
      url: https://github.com/Fi2zz/conatus.git
      ref: master
      path: packages/conatus        # 伞包：再导出全部 API

dependency_overrides:
  conatus_agent:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_agent}
  conatus_asr:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_asr}
  conatus_core:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_core}
  conatus_foundation:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_foundation}
  conatus_llm:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_llm}
  conatus_search:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_search}
```

```bash
dart pub get        # Flutter 项目用 flutter pub get
```

只依赖叶子包 `conatus_core`（无任何依赖）时不需要 override：

```yaml
dependencies:
  conatus_core:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_core}
```

依赖其他子包（如 `conatus_agent`、`conatus_search`、`conatus_tui`）时，需为它
传递依赖到的兄弟包补上对应的 `dependency_overrides`。

### 方案 B：本地 path 依赖（开发调试）

把上面每处 `git: {...}` 换成 `path: /你的路径/conatus/packages/<name>` 即可。

### 方案 C：发布后用版本号（推荐的长期方案）

将各包按依赖顺序发布到 pub.dev（`conatus_core` → `conatus_foundation` →
`conatus_llm` → `conatus_search` → `conatus_agent` → `conatus`），之后消费方只需：

```yaml
dependencies:
  conatus: ^0.15.0
```

## 开发

`dart pub get` 与 `dart analyze` 在仓库根目录一次完成；测试按包执行：

```bash
dart pub get
dart analyze
dart format .

# 运行全部包的测试（pub 暂不支持一次跑完整工作区）
for d in packages/*/; do (cd "$d" && dart test); done
```

## 文档

各包功能见其目录下的 README，完整的功能说明见
[`packages/conatus/README.md`](packages/conatus/README.md)。

## 许可证

[MIT](LICENSE)
