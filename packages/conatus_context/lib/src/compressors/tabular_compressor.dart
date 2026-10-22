/// 表格压缩：保表头与首尾行，中间按等距采样。
library;

import 'dart:math' as math;

import '../content_compressor.dart';
import '../content_kind.dart';
import '../text_lines.dart';

final RegExp _markdownSeparator = RegExp(r'^\s*\|?[\s:\-|]+\|');

/// CSV / TSV / markdown 表格压缩器。
class TabularCompressor implements ContentCompressor {
  const TabularCompressor();

  @override
  ContentKind get kind => ContentKind.tabular;

  @override
  CompressionDraft? compress(String input, CompressionBudget budget) {
    final List<String> lines = splitTextLines(input);
    final List<String> rows =
        lines.where((String line) => line.trim().isNotEmpty).toList();
    if (rows.length < 4) return null;
    final _Table? table = _readTable(rows);
    if (table == null || table.rows.length <= budget.maxItems) return null;
    final List<int> selected = _select(table.rows.length, budget.maxItems);
    final List<String> output = <String>[
      ...table.header,
      for (int i = 0; i < table.rows.length; i++)
        if (selected.contains(i)) table.rows[i],
    ];
    final int omitted = table.rows.length - selected.length;
    final int insertAt = table.header.length + math.max(0, selected.length - 5);
    output.insert(insertAt, _marker(table, omitted));
    return CompressionDraft(
      joinTextLines(output, crlf: usesCrlf(input)),
      itemsOmitted: omitted,
      unit: 'rows',
    );
  }

  _Table? _readTable(List<String> rows) {
    if (rows.first.contains('|') &&
        rows.length > 1 &&
        _markdownSeparator.hasMatch(rows[1])) {
      final int columns = rows.first.split('|').length - 2;
      return _Table(<String>[rows[0], rows[1]], rows.sublist(2),
          columns: columns);
    }
    for (final String delimiter in <String>[',', '\t', ';']) {
      if (_consistent(rows, delimiter)) {
        return _Table(<String>[rows.first], rows.sublist(1),
            columns: rows.first.split(delimiter).length, delimiter: delimiter);
      }
    }
    return null;
  }

  String _marker(_Table table, int omitted) {
    final String note = '[... $omitted rows omitted ...]';
    final List<String> cells = List<String>.filled(table.columns, '');
    cells[0] = note;
    final String? delimiter = table.delimiter;
    if (delimiter != null) return cells.join(delimiter);
    return '| ${cells.join(' | ')} |';
  }

  bool _consistent(List<String> rows, String delimiter) {
    final int expected = rows.first.split(delimiter).length;
    if (expected < 2) return false;
    int same = 0;
    for (final String row in rows) {
      if (row.split(delimiter).length == expected) same++;
    }
    return same / rows.length >= 0.9;
  }

  List<int> _select(int length, int maxItems) {
    final Set<int> keep = <int>{
      for (int i = 0; i < math.min(5, length); i++) i,
      for (int i = math.max(0, length - 5); i < length; i++) i,
    };
    final int slots = maxItems - keep.length;
    if (slots > 0) {
      final List<int> candidates = <int>[
        for (int i = 0; i < length; i++)
          if (!keep.contains(i)) i,
      ];
      final int count = math.min(slots, candidates.length);
      for (int i = 0; i < count; i++) {
        final double ratio = count == 1 ? 0 : i / (count - 1);
        keep.add(candidates[(ratio * (candidates.length - 1)).round()]);
      }
    }
    return keep.toList()..sort();
  }
}

class _Table {
  _Table(this.header, this.rows, {required this.columns, this.delimiter});

  final List<String> header;
  final List<String> rows;
  final int columns;
  final String? delimiter;
}
