import 'dart:convert';

import 'package:conatus_foundation/conatus_foundation.dart';

/// 图片 / PDF 附件读取：先 `stat` 看大小，超过 20 MiB 直接拒绝。
class ReadFileAttachments {
  const ReadFileAttachments(this._fs);

  final FileSystem _fs;

  /// 附件体积上限（20 MiB）。
  static const int maxAttachmentBytes = 20 * 1024 * 1024;

  /// 图片扩展名 → MIME；非图片返回 `null`。
  static String? imageMime(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0) return null;
    final String extension = path.substring(dot + 1).toLowerCase();
    return _imageMimes[extension];
  }

  /// 读取图片并作为 [ToolImage] 附件返回。
  Future<ToolResult> readImage(
    FsTarget target,
    String mimeType,
    String path,
  ) async {
    try {
      final ToolResult? tooLarge = await _checkSize(target, path, '图片');
      if (tooLarge != null) return tooLarge;
      final List<int> bytes = await _fs.readBytes(target);
      if (bytes.length > maxAttachmentBytes) {
        return _tooLarge(path, '图片');
      }
      return ToolResult.success(
        '图像已读取："$path"（${bytes.length} 字节，已作为图像附件返回）',
        images: <ToolImage>[
          ToolImage(mimeType: mimeType, base64Data: base64Encode(bytes)),
        ],
        value: <String, Object?>{
          'path': target.displayPath,
          'mimeType': mimeType,
          'bytes': bytes.length,
        },
      );
    } on UnsupportedError {
      return _unsupported(path);
    } on FsError catch (e) {
      return _error(e.code.code, e.message);
    }
  }

  /// 读取 PDF 并作为 [ToolFile] 附件返回（Anthropic / Responses 支持内联）。
  Future<ToolResult> readPdf(FsTarget target, String path) async {
    try {
      final ToolResult? tooLarge = await _checkSize(target, path, 'PDF');
      if (tooLarge != null) return tooLarge;
      final List<int> bytes = await _fs.readBytes(target);
      if (bytes.length > maxAttachmentBytes) {
        return _tooLarge(path, 'PDF');
      }
      return ToolResult.success(
        'PDF 已读取："$path"（${bytes.length} 字节，已作为文件附件返回）',
        files: <ToolFile>[
          ToolFile(
            mimeType: 'application/pdf',
            base64Data: base64Encode(bytes),
            filename: _basename(path),
          ),
        ],
        value: <String, Object?>{
          'path': target.displayPath,
          'mimeType': 'application/pdf',
          'bytes': bytes.length,
        },
      );
    } on UnsupportedError {
      return _unsupported(path);
    } on FsError catch (e) {
      return _error(e.code.code, e.message);
    }
  }

  /// 只读元数据判断体积，避免把整文件读进内存后才拒绝。
  Future<ToolResult?> _checkSize(
    FsTarget target,
    String path,
    String label,
  ) async {
    final FsInfo? info = await _fs.stat(target);
    final int? size = info?.size;
    if (size == null || size <= maxAttachmentBytes) return null;
    return _tooLarge(path, label);
  }

  ToolResult _tooLarge(String path, String label) =>
      _error('FS_TOO_LARGE', '$label超过 20 MiB："$path"');

  String _basename(String path) {
    final int slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }

  ToolResult _unsupported(String path) =>
      _error('FS_UNSUPPORTED', '当前文件系统不支持读取二进制："$path"');

  ToolResult _error(String code, String message) =>
      ToolResult.failure(message, error: ToolError(code, message));
}

const Map<String, String> _imageMimes = <String, String>{
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
};
