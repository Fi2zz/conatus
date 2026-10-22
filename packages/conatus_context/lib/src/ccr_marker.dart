/// CCR 身份与标记协议。
///
/// 标记形如 `<<ctx:0123456789abcdef 42_items_omitted>>`；id 由内容 hash 决定，
/// 读取时重算校验，不用于安全边界。
library;

/// 标记前缀。
const String kCcrMarkerPrefix = '<<ctx:';

/// 标记正则。
final RegExp _markerPattern =
    RegExp(r'<<ctx:([0-9a-f]{16}) (\d+)_([a-z]+)_omitted>>');

/// 由内容计算 16 位小写 hex 身份。
///
/// 取 FNV-1a 64 与 djb2 的低 32 位拼接；按 UTF-16 code unit 迭代，对同一内容
/// 稳定，碰撞由读取时的内容重算兜底。
String ccrIdOf(String content) {
  int fnv = 0xcbf29ce484222325;
  int djb = 5381;
  for (final int byte in content.codeUnits) {
    fnv = (fnv ^ byte) * 0x100000001b3;
    djb = ((djb << 5) + djb + byte) & 0xFFFFFFFF;
  }
  final int low = fnv & 0xFFFFFFFF;
  return '${low.toRadixString(16).padLeft(8, '0')}'
      '${djb.toRadixString(16).padLeft(8, '0')}';
}

/// 编码一个 CCR 标记。
String encodeCcrMarker(String id, int omitted, String unit) =>
    '$kCcrMarkerPrefix$id ${omitted}_${unit}_omitted>>';

/// 解析后的标记。
class CcrMarker {
  const CcrMarker({
    required this.id,
    required this.omitted,
    required this.unit,
  });

  /// CCR 身份。
  final String id;

  /// 省略的数量。
  final int omitted;

  /// 数量单位（items / lines / matches / hunks / rows）。
  final String unit;
}

/// 内容中是否含 CCR 标记。
bool containsCcrMarker(String content) => content.contains(kCcrMarkerPrefix);

/// 取内容中第一个合法标记；没有则返回 null。
CcrMarker? parseCcrMarker(String content) {
  final RegExpMatch? match = _markerPattern.firstMatch(content);
  if (match == null) return null;
  return CcrMarker(
    id: match.group(1)!,
    omitted: int.parse(match.group(2)!),
    unit: match.group(3)!,
  );
}
