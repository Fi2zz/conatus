/// conatus 的上下文压缩：结构化压缩工具结果并把原文存入 CCR。
library;

export 'src/ccr_marker.dart'
    show
        CcrMarker,
        ccrIdOf,
        containsCcrMarker,
        encodeCcrMarker,
        kCcrMarkerPrefix,
        parseCcrMarker;
export 'src/ccr_memory_store.dart' show CcrMemoryStore;
export 'src/ccr_store.dart' show CcrEntry, CcrStore;
export 'src/compression_result.dart' show ContextCompressionResult;
export 'src/compression_stats.dart' show CompressionStats, KindStats;
export 'src/compressors/json_array_compressor.dart' show JsonArrayCompressor;
export 'src/content_compressor.dart'
    show CompressionBudget, CompressionDraft, ContentCompressor;
export 'src/content_detector.dart'
    show ContentDetection, Detector, detectContent;
export 'src/content_kind.dart' show ContentKind;
export 'src/context_compression_config.dart' show ContextCompressionConfig;
