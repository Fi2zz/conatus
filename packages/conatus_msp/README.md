# conatus_msp

[实验性] conatus 的 Model Sensing Protocol（MSP）核心 Dart 实现。让本机进程通过共享目录自动发现，经真实 TCP 连接交换 Manifest、双向调用工具并主动推送事件。

本包是独立试验：只依赖 `conatus_core`，未接入伞包、Agent Loop、MCP 或 `ToolRegistry`。协议依据为 MSP `2026-10-10`，目前不宣称完整 conformance。

## 快速体验

```bash
cd packages/conatus_msp
dart run example/msp_demo.dart
```

Demo 使用真实 TCP 和临时目录启动两个节点，展示自动发现、工具调用、主动事件和资源清理，无需填写端口。

## 装配

```dart
final app = Context.root();
final node = MspNode(nodeId: 'consumer');
provideMsp(app, node);

node.on('notify.weather.*', (signal) {
  print('${signal.source}: ${signal.payload}');
});
await node.start();

app.dispose(); // 触发节点停止、连接关闭与声明撤销
```

提供者通过 `registerTool` 注册工具，通过 `declareSignal` 声明路径，通过 `publish` 广播事件。工具超时、对端不可达和断连以 `MspToolResult.error` 返回，不留下永久等待。

## 已实现

- Signal 八字段与 UTF-8 JSON；Manifest 握手结构
- 4 字节大端 TCP 帧，半包/粘包处理，16 MiB 上限
- HELLO/ACK、ping/pong、reqid 并发调用、错误作为值
- 发布广播、接收端路径过滤、可撤销订阅
- 共享目录原子声明、10 秒续租、30 秒过期和周期扫描
- `provideMsp` / `ctx.msp` 与 `Context.dispose()` 生命周期挂接

## 边界

- 仅用于同机、同一受信任用户和回环 TCP；没有 TLS、认证或授权。
- 信号不保留、不确认、不补发，也没有本地回环；离线订阅者会错过事件。
- 首版未实现 WebSocket / UDS / QUIC、HTTP registry / DHT、多轮交互、任务模式和动态 Manifest 更新。
- 节点启动后暂不支持动态注册工具或声明信号；请在 `start()` 前完成注册。
- MSP 与本包均处于 Alpha / 实验阶段，API 可能破坏性调整。
