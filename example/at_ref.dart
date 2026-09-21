// Playground 的 @ 文件引用：输入框 `@<路径>` 展开为 `<file>` 块注入对话。
//
// 经 PlaygroundController 覆写 handleLine 实现，不改 conatus_tui 库。

import 'dart:io';

import 'package:conatus_tui/conatus_tui.dart';

/// @ 引用单个文件的大小上限（超过不展开，保留原文并提示）。
const int kAtRefMaxBytes = 200 * 1024;

/// 会话控制器：发送前展开 `@<路径>` 文件引用。
class PlaygroundController extends ConatusTuiController {
  PlaygroundController({
    required super.app,
    required super.sessions,
    required super.name,
    required super.initialSession,
    required super.modelLabel,
    super.onExit,
  });

  @override
  Future<void> handleLine(String raw) async {
    final String line = raw.trim();
    if (line.isEmpty || line.startsWith('/')) {
      await super.handleLine(raw);
      return;
    }
    await super.handleLine(expandAtRefs(line));
  }
}

/// 把一行输入里的 `@<路径>` 逐个展开为 `<file path="...">内容</file>` 块。
String expandAtRefs(String line) {
  final StringBuffer buffer = StringBuffer();
  int cursor = 0;
  for (final RegExpMatch match in RegExp(r'@([^\s]+)').allMatches(line)) {
    buffer.write(line.substring(cursor, match.start));
    buffer.write(renderAtRef(match.group(1)!));
    cursor = match.end;
  }
  buffer.write(line.substring(cursor));
  return buffer.toString();
}

/// 单个引用的渲染：可读且未超限 → `<file>` 块；否则保留原文 + 提示。
String renderAtRef(String path) {
  try {
    final File file = File(path);
    if (!file.existsSync()) {
      return '@$path（文件不存在，未展开）';
    }
    final int length = file.lengthSync();
    if (length > kAtRefMaxBytes) {
      return '@$path（超过 ${kAtRefMaxBytes ~/ 1024}KB，未展开）';
    }
    final String content = file.readAsStringSync();
    return '<file path="$path">\n$content\n</file>';
  } catch (_) {
    return '@$path（读取失败，未展开）';
  }
}
