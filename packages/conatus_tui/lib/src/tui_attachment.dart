/// TUI 附件：粘贴/拖放进入输入栏的图片与文件。
///
/// 粘贴文本里识别出的文件路径（终端拖放产生）在这里登记为附件；提交时图片
/// 读字节转为 [LlmImage]，文本文件内联为 `<file>` 块（与 @ 引用同格式）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_llm/conatus_llm.dart';

/// 单图大小上限（字节）。
const int kAttachmentImageMaxBytes = 4 * 1024 * 1024;

/// 非图片（文本）附件内联上限，与 @ 引用一致（字节）。
const int kAttachmentFileMaxBytes = 200 * 1024;

/// 一次提交最多携带的附件数。
const int kAttachmentMaxCount = 8;

/// 图片扩展名 → MIME 类型。
const Map<String, String> kImageMimes = <String, String>{
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
};

/// 一条待发送的附件（文件已存在于磁盘）。
class TuiAttachment {
  const TuiAttachment({required this.path, required this.mimeType});

  /// 附件文件绝对路径。
  final String path;

  /// MIME 类型（按扩展名推断）。
  final String mimeType;

  /// 是否图片（作为多模态 parts 发送；否则内联文本）。
  bool get isImage => mimeType.startsWith('image/');

  /// 文件名（用于屏上展示）。
  String get name => path.split(Platform.pathSeparator).last;
}

/// 附件物化结果：随消息发送的图片与内联文本块。
class AttachmentMaterialization {
  const AttachmentMaterialization({
    required this.images,
    required this.inlineText,
  });

  /// 图片附件（base64）。
  final List<LlmImage> images;

  /// 文本附件拼接出的 `<file>` 块。
  final String inlineText;
}

/// 按扩展名推断 MIME；不认识时按纯文本处理。
String mimeFromPath(String path) {
  final String ext = path.split('.').last.toLowerCase();
  return kImageMimes[ext] ?? 'text/plain';
}

/// 从粘贴文本中识别文件路径附件。
///
/// 只有当全部非空 token 都对应到存在的文件时才返回附件列表；含普通文本、
/// 混合内容或超过数量上限时返回空（按普通文本粘贴处理）。相对路径以
/// [cwd] 为基准解析。
List<TuiAttachment> extractPathAttachments(String pastedText, String cwd) {
  final List<String> tokens = pastedText
      .split(RegExp(r'[\r\n]+'))
      .expand((String line) => line.split('\t'))
      .map(_cleanToken)
      .where((String token) => token.isNotEmpty)
      .toList();
  if (tokens.isEmpty || tokens.length > kAttachmentMaxCount) {
    return const <TuiAttachment>[];
  }
  final List<TuiAttachment> found = <TuiAttachment>[];
  for (final String token in tokens) {
    final String path = _resolvePath(token, cwd);
    if (!File(path).existsSync()) return const <TuiAttachment>[];
    found.add(TuiAttachment(path: path, mimeType: mimeFromPath(path)));
  }
  return found;
}

/// 附件物化：图片 → [LlmImage]（超限抛 [StateError]）；文本 → `<file>` 块。
Future<AttachmentMaterialization> materializeAttachments(
  List<TuiAttachment> attachments,
) async {
  final List<LlmImage> images = <LlmImage>[];
  final StringBuffer inline = StringBuffer();
  for (final TuiAttachment attachment in attachments) {
    final List<int> bytes = await File(attachment.path).readAsBytes();
    if (attachment.isImage) {
      if (bytes.length > kAttachmentImageMaxBytes) {
        throw StateError('图片 ${attachment.name} 超过 4MB 上限');
      }
      images.add(LlmImage(
        mimeType: attachment.mimeType,
        base64Data: base64Encode(bytes),
      ));
      continue;
    }
    if (bytes.length > kAttachmentFileMaxBytes) {
      throw StateError('文件 ${attachment.name} 超过 200KB 上限');
    }
    final String content = utf8.decode(bytes, allowMalformed: true);
    inline.write('<file path="${attachment.path}">\n$content\n</file>\n');
  }
  return AttachmentMaterialization(images: images, inlineText: inline.toString());
}

/// 去掉引号与空白。
String _cleanToken(String raw) => raw.trim().replaceAll('"', '').replaceAll("'", '');

/// 解析 token：去 `file://` 前缀；相对路径拼 [cwd]。
String _resolvePath(String token, String cwd) {
  String path = token;
  const String scheme = 'file://';
  if (path.startsWith(scheme)) path = path.substring(scheme.length);
  if (path.startsWith('/')) return path;
  return '$cwd/$path';
}
