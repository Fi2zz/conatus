/// conatus 的可观测性能力：span 语义与从 Session Log 派生的 TraceBuilder。
///
/// 后续步骤在此追加 OTel / Prometheus / JSONL 导出器与成本追踪。
library;

export 'src/otel/span.dart';
export 'src/trace/trace_builder.dart';
