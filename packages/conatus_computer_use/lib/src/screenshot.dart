/// 屏幕截图、区域与附件存储。
library;

import 'dart:convert';
import 'dart:typed_data';

/// 屏幕区域（纯 Dart 值类型，等价于 DSH 的 `Rect`）。
class ScreenRegion {
  const ScreenRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// 左上角 x。
  final int x;

  /// 左上角 y。
  final int y;

  /// 宽度。
  final int width;

  /// 高度。
  final int height;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  /// 从 JSON 解析；字段缺失退回 0。
  factory ScreenRegion.fromJson(Map<String, Object?> json) => ScreenRegion(
        x: json['x'] as int? ?? 0,
        y: json['y'] as int? ?? 0,
        width: json['width'] as int? ?? 0,
        height: json['height'] as int? ?? 0,
      );
}

/// 屏幕截图。
class Screenshot {
  const Screenshot({
    required this.bytes,
    required this.width,
    required this.height,
    required this.capturedAt,
    this.mimeType = 'image/png',
    this.attachmentRef,
  });

  /// 图像字节。
  final List<int> bytes;

  /// 宽度。
  final int width;

  /// 高度。
  final int height;

  /// 捕获时间。
  final DateTime capturedAt;

  /// MIME 类型。
  final String mimeType;

  /// 持久化后的附件引用 ID（[AttachmentStore.save] 的返回值）。
  final String? attachmentRef;

  /// 是否为空。
  bool get isEmpty => bytes.isEmpty;

  /// 复制并覆盖部分字段。
  Screenshot copyWith({
    List<int>? bytes,
    int? width,
    int? height,
    DateTime? capturedAt,
    String? mimeType,
    String? attachmentRef,
  }) =>
      Screenshot(
        bytes: bytes ?? this.bytes,
        width: width ?? this.width,
        height: height ?? this.height,
        capturedAt: capturedAt ?? this.capturedAt,
        mimeType: mimeType ?? this.mimeType,
        attachmentRef: attachmentRef ?? this.attachmentRef,
      );
}

/// 附件存储。用于持久化截图。
abstract class AttachmentStore {
  /// 保存附件，返回引用 ID。
  Future<String> save(List<int> bytes, {required String mimeType});

  /// 按引用 ID 加载附件。
  Future<List<int>?> load(String ref);

  /// 删除附件。
  Future<void> delete(String ref);
}

/// 进程内内存附件存储（测试与无后端场景）。
class InMemoryAttachmentStore implements AttachmentStore {
  final Map<String, List<int>> _items = <String, List<int>>{};
  int _next = 0;

  /// 已保存的引用 ID。
  List<String> get refs => _items.keys.toList(growable: false);

  @override
  Future<String> save(List<int> bytes, {required String mimeType}) async {
    final String ref = 'attachment-${_next++}';
    _items[ref] = Uint8List.fromList(bytes);
    return ref;
  }

  @override
  Future<List<int>?> load(String ref) async => _items[ref];

  @override
  Future<void> delete(String ref) async {
    _items.remove(ref);
  }
}

/// 从 base64 字符串解码字节（MCP 图像内容的 `data` 字段形态）。
List<int> decodeBase64Bytes(String data) => base64Decode(data);

/// 编码为 base64 字符串。
String encodeBase64Bytes(List<int> bytes) => base64Encode(bytes);
