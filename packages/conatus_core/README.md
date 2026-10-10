# conatus_core

conatus 的核心范式——时空可组合性编程模型，**零运行时依赖**（仅 Dart
核心库）。同时是 `conatus` 全部模块包的公共底座。

- `EffectScope` — 可逆效应的 LIFO 撤销（时间可组合性）
- `Reactor` — 服务变更的同步广播与重入收敛（空间可组合性调度）
- `Context` — 统一上下文，同时承载效应与共效应
- `isSensitiveKey` / `maskSecret` / `redactSecrets` — 密钥脱敏：判定敏感
  键名、遮蔽单个值（前 4 + `...` + 后 4，长度 ≤ 8 时整串星号）、递归清洗
  Map / List（不改入参）

## 用法

```dart
import 'package:conatus_core/conatus_core.dart';

final app = Context.root(name: 'app');
final stop = app.provide('logger', Logger());
app.inject(['logger'], (ctx) => ctx.require<Logger>('logger').info('hi'));
stop(); // logger 消失，依赖它的 inject 自动停用
app.dispose();
```

## 核心语义

**服务（provide / get / require / has）**：服务沿父链向下可见——子上下文
能看到父上下文的服务，父级**永远看不到**子级。`get` 沿父链查找，`require`
找不到时抛 `StateError`。`provide` 返回 `Disposer`，提前撤销可级联停用
依赖方。

**效应（track / effect / onDispose）**：每次副作用登记一个撤销函数，
`dispose` 按 **LIFO** 顺序回滚。`EffectScope` 有三条硬保证：

1. **幂等**：重复 `dispose` 不会重复执行撤销函数；
2. **迟到安全**：释放后再 `track`，撤销函数**立即执行**（而不是被静默丢弃）；
3. **抗异常**：单个撤销函数抛异常不阻断其余，错误聚合返回。

**共效应（inject）**：`ctx.inject([...], (child) {...})` 声明依赖；运行时
持续比对当前上下文，依赖全部可见时在**全新子上下文**中激活，任一依赖消失
时子上下文被释放、其所有效应回滚。每次激活状态都是纯净的。

**Reactor**：服务变更用「脏标记 + 重跑」把连锁反应在一次 `notify()` 内
收敛；无法收敛（循环依赖）抛 `StateError` 快速失败，`maxRounds` 默认 100。

## 设计约束（不可违反）

1. 服务对父级不可见（层级作用域的必然结果，避免插件互相污染；跨子树通信
   用「共享槽位」模式）。
2. inject 激活时创建全新子上下文。
3. `EffectScope` 幂等 + 迟到安全。
4. `Reactor` 重入收敛失败抛 `StateError`，不静默死循环。
5. 零运行时依赖。

## 注意

- `inject` 回调抛的异常交给 Zone：`evaluate` 在 `notify` 期间被调用，
  调用栈已断开，无法同步冒泡。
- `EffectScope.dispose` 返回错误列表而非抛异常：卸载需要「尽可能多清理」。
- `redactSecrets` 不修改入参，返回清洗后的新结构。

完整机制讲解、插件装配与全部模块包 API 见仓库根
[README](../../README.md)；贡献与约定见 [AGENTS.md](../../AGENTS.md)。
