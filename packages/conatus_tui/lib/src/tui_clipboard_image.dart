/// 系统剪贴板图片读取（macOS）。
///
/// 终端粘贴传不进图片二进制：Cmd+V 时终端只写文本，剪贴板里是图片则无事
/// 发生。用户改按 Ctrl+V（终端把 `^V` 字面交给 TUI），这里经 osascript 取
/// `«class PNGf»` 读出图片字节。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_llm/conatus_llm.dart';

/// 读取剪贴板中的图片；无图片、非 macOS 或执行失败时返回 null。
Future<LlmImage?> readClipboardImage() async {
  if (!Platform.isMacOS) return null;
  final ProcessResult result;
  try {
    result = await Process.run('/usr/bin/osascript', const <String>[
      '-e',
      'the clipboard as «class PNGf»',
    ]);
  } catch (_) {
    return null;
  }
  if (result.exitCode != 0) return null;
  final String? base64 = pngBase64FromOsa('${result.stdout}');
  if (base64 == null) return null;
  return LlmImage(mimeType: 'image/png', base64Data: base64);
}

/// 解析 osascript 输出（`«data PNGf<十六进制>»`）为 base64；不匹配返回 null。
String? pngBase64FromOsa(String output) {
  final RegExpMatch? match =
      RegExp(r'«data PNGf([0-9A-Fa-f]+)»').firstMatch(output);
  final String? hex = match?.group(1);
  if (hex == null || hex.isEmpty) return null;
  final List<int> bytes = <int>[
    for (int i = 0; i + 1 < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  return base64Encode(bytes);
}
