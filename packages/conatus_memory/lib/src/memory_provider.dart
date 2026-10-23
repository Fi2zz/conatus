/// 装配：把记忆写入能力挂到 `agentLoop` 上。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'memory_recorder.dart';
import 'memory_write_policy.dart';

/// 提供记忆写入能力：`agentLoop` 出现时挂上 [MemoryRecorder]，消失时自动摘除。
///
/// 依赖 `'memory'` 服务（`provideMemory`）。返回记录器，宿主可读取或替换。
MemoryRecorder provideMemoryRecorder(
  Context ctx, {
  MemoryStore? memory,
  MemoryWritePolicy? policy,
  void Function(MemoryWriteDecision decision)? onStore,
}) {
  final MemoryStore store = memory ?? ctx.require<MemoryStore>('memory');
  final MemoryRecorder recorder = MemoryRecorder(
    memory: store,
    policy: policy ?? const PolicyMemoryWritePolicy(),
    onStore: onStore,
  );
  ctx.inject(<String>['agentLoop'], (Context child) {
    final AgentLoop agent = child.require<AgentLoop>('agentLoop');
    child.effect(() => agent.addTurnTracker(recorder));
  });
  return recorder;
}
