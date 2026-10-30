/// 工具结果驱逐内核：把超阈值的正文落盘，上下文只留预览 + 路径。
///
/// [ToolResultEviction] 只做「落盘 + 预览 + 清理」三件事，不感知调用管线；
/// 中间件装配见 conatus_agent 的 `provideToolResultEviction`。
library;

import 'dart:io';

import 'fs.dart';

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
        '完整内容已写入文件：$path\n（需要细节时调用 read 读取该路径）';
  }

  String _path() {
    final String base = dir ??
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
            'conatus_tool_results';
    return '$base${Platform.pathSeparator}'
        'tool-${DateTime.now().microsecondsSinceEpoch}-${_spilled.length}.txt';
  }
}
