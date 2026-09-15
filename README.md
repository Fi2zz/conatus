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
| [`conatus_agent`](packages/conatus_agent) | Agent Loop 与产品化：plan / sub-agent / reflection / telemetry / eval / approval / skill / recovery | `conatus_core`、`conatus_foundation`、`conatus_llm` |
| [`conatus`](packages/conatus) | 伞包（umbrella）：再导出以上全部，保持 `package:conatus/conatus.dart` 兼容 | 全部 |

依赖方向自上而下，无环：

```
conatus ─▶ conatus_agent ─▶ conatus_llm ─▶ conatus_core
                │                              ▲
                └▶ conatus_foundation ─────────┘
conatus_search ─▶ conatus_foundation
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
