/// 记忆写入策略能力：把「一条内容值不值得长期保留」从 Agent Loop 里拿出来，
/// 作为可插拔能力接入。
///
/// 机制（存 / 召回 / 遗忘 / 容量）在 `conatus_foundation` 的 `MemoryStore`；
/// 本包只提供判定规则、轮次记录器与装配函数。
library;

export 'src/memory_provider.dart' show provideMemoryRecorder;
export 'src/memory_recorder.dart' show MemoryRecorder;
export 'src/memory_write_policy.dart'
    show
        MemoryWriteDecision,
        MemoryWritePolicy,
        MemoryWriteVerdict,
        PolicyMemoryWritePolicy,
        kDefaultGreetings;
