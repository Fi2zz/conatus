/// @ 文件引用：把输入行里的 `@<路径>` 展开为 `<file path="...">内容</file>` 块。
///
/// 由 [ConatusTuiController.handleLine] 发送前调用；找不到 / 超限 / 读失败时
/// 保留原文并追加提示，不阻塞对话。相对路径以注入 [FileSystem] 的 cwd 为基准。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// @ 引用单个文件的大小上限（字节；超过不展开，保留原文并提示）。
const int kAtRefMaxBytes = 200 * 1024;

/// 一行里最多展开的 @ 引用数（超出部分原样保留）。
const int kAtRefMaxCount = 8;

/// 把 [line] 里的 `@<路径>` 逐个展开为 `<file path="...">内容</file>` 块。
///
/// [fs] 不可用时原样返回；单处展开失败（不存在 / 超限 / 读失败）保留原文并
/// 在引用处追加一行提示。
Future<String> expandAtRefs(String line, {FileSystem? fs}) async {
  if (fs == null) return line;
  final StringBuffer buffer = StringBuffer();
  int cursor = 0;
  int count = 0;
  for (final RegExpMatch match in RegExp(r'@([^\s]+)').allMatches(line)) {
    if (count >= kAtRefMaxCount) break;
    buffer.write(line.substring(cursor, match.start));
    buffer.write(await _renderAtRef(match.group(1)!, fs));
    cursor = match.end;
    count++;
  }
  buffer.write(line.substring(cursor));
  return buffer.toString();
}

/// 单个引用的渲染：可读且未超限 → `<file>` 块；否则保留原文 + 提示。
Future<String> _renderAtRef(String path, FileSystem fs) async {
  try {
    final FsTarget target = await fs.resolve(path);
    final FsInfo? info = await fs.stat(target);
    if (info == null || info.type != FsFileType.file) {
      return '@$path（文件不存在，未展开）';
    }
    if (info.size != null && info.size! > kAtRefMaxBytes) {
      return '@$path（超过 ${kAtRefMaxBytes ~/ 1024}KB，未展开）';
    }
    final String content = await fs.readText(target);
    if (content.length > kAtRefMaxBytes) {
      return '@$path（超过 ${kAtRefMaxBytes ~/ 1024}KB，未展开）';
    }
    return '<file path="$path">\n$content\n</file>';
  } catch (_) {
    return '@$path（读取失败，未展开）';
  }
}
