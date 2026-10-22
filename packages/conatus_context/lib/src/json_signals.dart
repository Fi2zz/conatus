/// JSON 数组压缩的保真信号：错误项与统计异常值。
library;

final RegExp _errorWords = RegExp(
  r'error|fatal|fail|exception|timeout|denied|panic|stack',
  caseSensitive: false,
);

/// 条目是否含错误信号。
bool jsonItemHasErrorSignal(Object? item) {
  if (item is String) return _errorWords.hasMatch(item);
  if (item is! Map<String, Object?>) return false;
  for (final MapEntry<String, Object?> entry in item.entries) {
    if (_errorWords.hasMatch(entry.key)) return true;
    final Object? value = entry.value;
    if (value is String && _errorWords.hasMatch(value)) return true;
    if (value is num && _statusLike(entry.key) && value >= 400) return true;
  }
  return false;
}

bool _statusLike(String key) =>
    key == 'status' || key == 'code' || key.endsWith('Code');

/// 找出数值字段落在 1% / 99% 分位之外的条目。
Set<int> jsonOutlierIndices(List<Object?> items) {
  final Map<String, List<({int index, double value})>> values =
      <String, List<({int index, double value})>>{};
  for (int i = 0; i < items.length; i++) {
    final Object? item = items[i];
    if (item is! Map<String, Object?>) continue;
    for (final MapEntry<String, Object?> entry in item.entries) {
      final Object? value = entry.value;
      if (value is num && value.isFinite) {
        values
            .putIfAbsent(entry.key, () => <({int index, double value})>[])
            .add((index: i, value: value.toDouble()));
      }
    }
  }
  final Set<int> outliers = <int>{};
  for (final List<({int index, double value})> list in values.values) {
    if (list.length < 20) continue;
    final List<({int index, double value})> sorted = list.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final double low = sorted[((sorted.length - 1) * 0.01).floor()].value;
    final double high = sorted[((sorted.length - 1) * 0.99).floor()].value;
    for (final ({int index, double value}) point in sorted) {
      if (point.value < low || point.value > high) outliers.add(point.index);
    }
  }
  return outliers;
}
