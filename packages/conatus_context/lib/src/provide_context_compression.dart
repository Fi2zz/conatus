/// 装配：把 Router 接到工具结果中间件，并注册 CCR 工具。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'ccr_file_store.dart';
import 'ccr_memory_store.dart';
import 'ccr_store.dart';
import 'compression_result.dart';
import 'compression_stats.dart';
import 'content_compressor.dart';
import 'context_compression_config.dart';
import 'context_retrieval_tool.dart';
import 'context_router.dart';
import 'context_stats_tool.dart';

/// 本包自有工具：它们的结果不再参与压缩，避免取回原文时被再次压缩。
const Set<String> _selfTools = <String>{
  'context_retrieve',
  'context_stats',
};

/// 装配后的服务句柄。
class ContextCompressionService {
  const ContextCompressionService({
    required this.router,
    required this.stats,
    required this.store,
  });

  /// 压缩路由。
  final ContextRouter router;

  /// 统计。
  final CompressionStats stats;

  /// CCR 存储。
  final CcrStore store;
}

/// `ctx.contextCompressor`：当前上下文可见的压缩服务。
extension ContextCompressionContext on Context {
  /// 取压缩服务；未装配时为 null。
  ContextCompressionService? get contextCompressor =>
      get<ContextCompressionService>('contextCompressor');
}

/// 装配上下文压缩，返回服务句柄。
///
/// 中间件标签为 `contextCompression`。若同时使用 `tool-result-eviction`，
/// 应先装驱逐器、再调用本函数：后注册的中间件在内层，压缩先处理工具原始结果，
/// 压缩后仍超限的内容再由外层驱逐器落盘。
ContextCompressionService provideContextCompression(
  Context ctx, {
  ContextCompressionConfig? config,
  CcrStore? store,
  ToolRegistry? tools,
  FileSystem? fs,
  String? dir,
  List<ContentCompressor>? compressors,
}) {
  final ContextCompressionConfig resolved = config ??
      ctx.get<ContextCompressionConfig>('contextCompressionConfig') ??
      const ContextCompressionConfig();
  final ToolRegistry registry = tools ?? ctx.tools;
  final CcrStore ccr = store ?? _resolveStore(ctx, resolved, fs, dir);
  final CompressionStats stats = CompressionStats();
  final ContextRouter router = ContextRouter(
    config: resolved,
    store: ccr,
    compressors: compressors,
    stats: stats,
  );
  final ContextCompressionService service = ContextCompressionService(
    router: router,
    stats: stats,
    store: ccr,
  );
  ctx.provide('contextCompressor', service);
  ctx.effect(() => registry.use(
        (ToolCall call, Future<ToolResult> Function() next) =>
            _compressResult(call, next, router, resolved),
        tag: 'contextCompression',
      ));
  if (resolved.ccrEnabled) {
    ctx.effect(() => registry.register(
          ContextRetrievalTool(ccr, onHit: stats.countCcrHit),
        ));
  }
  ctx.effect(() => registry.register(ContextStatsTool(stats)));
  return service;
}

CcrStore _resolveStore(
  Context ctx,
  ContextCompressionConfig config,
  FileSystem? fs,
  String? dir,
) {
  if (dir == null) {
    return CcrMemoryStore(
      maxEntries: config.ccrMaxEntries,
      ttl: config.ccrTtl,
    );
  }
  return CcrFileStore(
    fs: fs ?? ctx.require<FileSystem>('fs'),
    dir: dir,
    maxEntries: config.ccrMaxEntries,
    ttl: config.ccrTtl,
  );
}

Future<ToolResult> _compressResult(
  ToolCall call,
  Future<ToolResult> Function() next,
  ContextRouter router,
  ContextCompressionConfig config,
) async {
  final ToolResult result = await next();
  if (_selfTools.contains(call.name)) return result;
  if (!config.enabled) return result;
  if (result.isError && !config.compressToolErrors) return result;
  final ContextCompressionResult compressed = await router.compress(
    result.content,
    toolName: call.name,
    conservative: result.isError,
  );
  if (!compressed.applied) return result;
  if (result.isError) {
    return ToolResult.failure(compressed.content, error: result.error);
  }
  return ToolResult.success(
    compressed.content,
    value: _mergedValue(result.value, compressed),
  );
}

Map<String, Object?> _mergedValue(
  Object? value,
  ContextCompressionResult compressed,
) {
  final Map<String, Object?> merged = <String, Object?>{};
  if (value is Map<Object?, Object?>) {
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      merged['${entry.key}'] = entry.value;
    }
  } else {
    merged['originalValue'] = value;
  }
  merged['contextCompressed'] = true;
  merged['kind'] = compressed.kind.name;
  merged['ccrId'] = compressed.ccrId;
  merged['originalChars'] = compressed.beforeChars;
  return merged;
}
