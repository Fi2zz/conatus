/// conatus 的压缩能力缝：服务契约、日志事件、切点安全与默认压缩器。
library;

export 'src/compaction.dart' show Compactor, provideCompaction;
export 'src/compaction_engine.dart' show CompactionEngine;
export 'src/compaction_invariant.dart'
    show assertCompactionInvariant, checkCompactionInvariant;
export 'src/compaction_tool_pairing.dart'
    show
        balancedCutAtOrBefore,
        toolPairingBalancedAfter,
        toolPairingBalancedBefore;
export 'src/compaction_types.dart'
    show
        CompactionFold,
        CompactionId,
        CompactionResult,
        CompactionSummary,
        Summarizer,
        kCompactionEndEvent,
        kCompactionStartEvent,
        kCompactionSummaryEvent,
        nextCompactionId;
