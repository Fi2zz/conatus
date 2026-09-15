# conatus_core

conatus 的核心范式（零运行时依赖）：

- `EffectScope` — 可逆效应的 LIFO 撤销（时间可组合性）
- `Reactor` — 服务变更的同步广播与重入收敛（空间可组合性调度）
- `Context` — 统一上下文，同时承载效应与共效应

```dart
import 'package:conatus_core/conatus_core.dart';

final app = Context.root(name: 'app');
final stop = app.provide('logger', Logger());
app.inject(['logger'], (ctx) => ctx.require<Logger>('logger').info('hi'));
stop(); // logger 消失，依赖它的 inject 自动停用
app.dispose();
```

完整说明见仓库根 [README](../../README.md)。
