/// tool-result-eviction 装配：把 [ToolResultEviction] 挂进工具调用管线。
///
/// 在 [ToolRegistry.use] 上加一层环绕中间件：工具返回成功且正文超过阈值时，
/// 把完整内容写入临时文件，正文替换为「前 N 字符 + 省略提示 + 后 N 字符 +
/// 路径」，模型需要细节时用 `read` 读取。失败结果不驱逐。落盘内核见
/// conatus_foundation 的 `src/tool_result_eviction.dart`。
///
/// ```dart
/// provideToolResultEviction(app, threshold: 80000);
/// // 或先 provide('toolResultThreshold', 80000) 再调用
/// ```
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

/// 安装工具结果驱逐中间件，返回驱逐器。
///
/// 阈值取 [threshold]，否则取上下文里 `'toolResultThreshold'`（int），再否则
/// [kDefaultToolResultThreshold]。中间件与临时文件都随上下文释放撤销/清理。
ToolResultEviction provideToolResultEviction(
  Context ctx, {
  ToolResultEviction? eviction,
  FileSystem? fs,
  ToolRegistry? tools,
  int? threshold,
  int previewChars = kDefaultToolResultPreview,
  String? dir,
}) {
  final FileSystem resolvedFs = fs ?? ctx.require<FileSystem>('fs');
  final ToolRegistry registry = tools ?? ctx.tools;
  final int resolvedThreshold = threshold ??
      ctx.get<int>('toolResultThreshold') ??
      kDefaultToolResultThreshold;
  final ToolResultEviction resolved = eviction ??
      ToolResultEviction(
        fs: resolvedFs,
        threshold: resolvedThreshold,
        previewChars: previewChars,
        dir: dir,
      );

  ctx.effect(() => registry.use(
        (ToolCall call, Future<ToolResult> Function() next) async {
          final ToolResult result = await next();
          if (result.isError) return result;
          final String? preview = await resolved.evict(result.content);
          if (preview == null) return result;
          return ToolResult.success(
            preview,
            value: <String, Object?>{
              'spilled': true,
              'path': resolved.spilledPaths.last,
              'originalChars': result.content.length,
            },
          );
        },
      ));
  ctx.onDispose(() => unawaited(resolved.clear()));
  return resolved;
}
