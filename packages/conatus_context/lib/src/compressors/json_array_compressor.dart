/// JSON 数组结构化压缩：保结构、保错误、保首尾，其余按统计采样。
library;

import 'dart:convert';
import 'dart:math' as math;

import '../ccr_marker.dart';
import '../content_compressor.dart';
import '../content_kind.dart';

final RegExp _errorWords = RegExp(
  r'error|fatal|fail|exception|timeout|denied|panic|stack',
  caseSensitive: false,
);

/// 顶层 JSON 数组压缩器。
class JsonArrayCompressor implements ContentCompressor {
  const JsonArrayCompressor();

  @override
  ContentKind get kind => ContentKind.jsonArray;

  @override
  CompressionDraft? compress(String input, CompressionBudget budget) {
    final String text = input.startsWith('\uFEFF') ? input.substring(1) : input;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! List<Object?> || decoded.isEmpty) return null;
    if (_depth(decoded) > 32) return null;
    final List<int> selected = _select(decoded, budget.maxItems);
    final int omitted = decoded.length - selected.length;
    final List<Object?> output = <Object?>[
      for (final int index in selected) decoded[index],
    ];
    if (omitted > 0) {
      output.add(_note(decoded.first, omitted, budget.retrievalId));
    }
    return CompressionDraft(
      jsonEncode(output),
      itemsOmitted: omitted,
    );
  }

  Object _note(Object? first, int omitted, String retrievalId) {
    final String marker = retrievalId.isEmpty
        ? ''
        : ' ${encodeCcrMarker(retrievalId, omitted, 'items')}';
    final String text =
        '$omitted items omitted;$marker use context_retrieve to read the original';
    return first is Map ? <String, Object?>{'_conatus_context': text} : text;
  }

  List<int> _select(List<Object?> items, int maxItems) {
    if (items.length <= maxItems) {
      return <int>[for (int i = 0; i < items.length; i++) i];
    }
    final List<int> deduped = _dedupedIndices(items);
    final Set<int> keep = <int>{
      ...deduped.take(2),
      ...deduped.skip(math.max(0, deduped.length - 2)),
      for (final int index in deduped)
        if (_errorSignal(items[index])) index,
      ..._outlierIndices(items),
    };
    final List<int> candidates =
        deduped.where((int index) => !keep.contains(index)).toList();
    final int slots = maxItems - keep.length;
    if (slots > 0 && candidates.isNotEmpty) {
      _fillSlots(keep, candidates, slots);
    }
    final List<int> selected = keep.toList()..sort();
    return selected;
  }

  void _fillSlots(Set<int> keep, List<int> candidates, int slots) {
    final int count = math.min(slots, candidates.length);
    final int target = keep.length + count;
    for (int slot = 0; slot < count; slot++) {
      final double ratio = count == 1 ? 0 : slot / (count - 1);
      keep.add(candidates[(ratio * (candidates.length - 1)).round()]);
    }
    for (final int index in candidates) {
      if (keep.length >= target) break;
      keep.add(index);
    }
  }

  List<int> _dedupedIndices(List<Object?> items) {
    final Set<String> seen = <String>{};
    final List<int> indices = <int>[];
    for (int i = 0; i < items.length; i++) {
      if (seen.add(jsonEncode(_canonical(items[i])))) indices.add(i);
    }
    return indices;
  }

  Object? _canonical(Object? value) {
    if (value is Map<String, Object?>) {
      final List<String> keys = value.keys.toList()..sort();
      return <String, Object?>{
        for (final String key in keys) key: _canonical(value[key]),
      };
    }
    if (value is List<Object?>) return value.map(_canonical).toList();
    return value;
  }

  bool _errorSignal(Object? item) {
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
      key == 'status' || key.endsWith('Code') || key == 'code';

  Set<int> _outlierIndices(List<Object?> items) {
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

  int _depth(Object? value) {
    if (value is List<Object?>) {
      if (value.isEmpty) return 1;
      return 1 + value.map(_depth).reduce(math.max);
    }
    if (value is Map<String, Object?>) {
      if (value.isEmpty) return 1;
      return 1 + value.values.map(_depth).reduce(math.max);
    }
    return 1;
  }
}
