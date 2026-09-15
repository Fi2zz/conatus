/// tool-result-eviction 插件：把超阈值的工具结果落盘，上下文只留预览 + 路径。
///
/// 在 [ToolRegistry.use] 上加一层环绕中间件：工具返回成功且正文超过阈值时，
/// 把完整内容写入临时文件，正文替换为「前 N 字符 + 省略提示 + 后 N 字符 +
/// 路径」，模型需要细节时用 `read_file` 读取。失败结果不驱逐。
///
/// ```dart
/// provideToolResultEviction(app, threshold: 80000);
/// // 或先 provide('toolResultThreshold', 80000) 再调用
/// ```
library;

import 'dart:async';
import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

/// 默认驱逐阈值（字符数）。
const int kDefaultToolResultThreshold = 80000;

/// 默认预览每侧字符数。
const int kDefaultToolResultPreview = 2000;

/// 工具结果驱逐器：落盘 + 预览 + 清理。
class ToolResultEviction {
  ToolResultEviction({
    required this.fs,
    this.threshold = kDefaultToolResultThreshold,
    this.previewChars = kDefaultToolResultPreview,
    this.dir,
  });

  /// 落盘用的文件系统。
  final FileSystem fs;

  /// 超过该字符数即落盘。
  final int threshold;

  /// 预览保留的头/尾字符数。
  final int previewChars;

  /// 临时文件目录；缺省用系统临时目录下的 `conatus_tool_results`。
  final String? dir;

  final List<String> _spilled = <String>[];

  /// 已落盘的临时文件路径。
  List<String> get spilledPaths => List<String>.unmodifiable(_spilled);

  /// 正文超过阈值时落盘并返回预览；否则返回 `null`（调用方保留原结果）。
  Future<String?> evict(String content) async {
    if (content.length <= threshold) return null;
    final FsTarget target = await fs.resolve(_path());
    await fs.writeText(target, content);
    _spilled.add(target.displayPath);
    final int preview =
        previewChars * 2 >= content.length ? content.length ~/ 2 : previewChars;
    return _preview(content, target.displayPath, preview);
  }

  /// 删除全部已落盘文件。幂等。
  Future<void> clear() async {
    for (final String path in List<String>.of(_spilled)) {
      await fs.remove(await fs.resolve(path));
    }
    _spilled.clear();
  }

  String _preview(String content, String path, int preview) {
    final String head = content.substring(0, preview);
    final String tail = content.substring(content.length - preview);
    final int omitted = content.length - preview * 2;
    return '$head\n\n...(省略 $omitted 字符)...\n\n$tail\n\n'
        '完整内容已写入文件：$path\n（需要细节时调用 read_file 读取该路径）';
  }

  String _path() {
    final String base = dir ??
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
            'conatus_tool_results';
    return '$base${Platform.pathSeparator}'
        'tool-${DateTime.now().microsecondsSinceEpoch}-${_spilled.length}.txt';
  }
}

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
