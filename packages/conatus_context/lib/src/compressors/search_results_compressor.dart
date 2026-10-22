/// 搜索结果压缩：按文件聚合，保留首尾与错误行，其余均匀采样。
library;

import 'dart:math' as math;

import '../content_compressor.dart';
import '../content_kind.dart';
import '../text_lines.dart';

final RegExp _searchLine = RegExp(r'^(\S.*?)[:\-](\d+)[:\-](.*)$');
final RegExp _errorWords = RegExp(
  r'error|fatal|fail|exception|timeout|denied|panic|stack',
  caseSensitive: false,
);

class _Match {
  _Match(this.index, this.line, this.lineNumber, this.text);

  final int index;
  final String line;
  final int lineNumber;
  final String text;

  bool get error => _errorWords.hasMatch(text);
}

class _FileGroup {
  _FileGroup(this.path);

  final String path;
  final List<_Match> matches = <_Match>[];
}

/// grep / ripgrep 结果压缩器。
class SearchResultsCompressor implements ContentCompressor {
  const SearchResultsCompressor();

  @override
  ContentKind get kind => ContentKind.searchResults;

  @override
  CompressionDraft? compress(String input, CompressionBudget budget) {
    final List<String> lines = splitTextLines(input);
    final Map<String, _FileGroup> groups = <String, _FileGroup>{};
    int total = 0;
    for (int i = 0; i < lines.length; i++) {
      final RegExpMatch? match = _searchLine.firstMatch(lines[i]);
      if (match == null) continue;
      final String path = match.group(1)!;
      groups.putIfAbsent(path, () => _FileGroup(path)).matches.add(
            _Match(i, lines[i], int.parse(match.group(2)!), match.group(3)!),
          );
      total++;
    }
    if (total < 3 || groups.isEmpty) return null;
    final List<_FileGroup> kept = _selectFiles(groups, budget.maxFiles);
    final Set<int> selected = _mandatory(kept);
    _fill(kept, selected, budget.maxLines);
    final int omitted = total - selected.length;
    return CompressionDraft(
      _render(kept, groups, selected, total, usesCrlf(input)),
      itemsOmitted: omitted,
      unit: 'matches',
    );
  }

  List<_FileGroup> _selectFiles(
    Map<String, _FileGroup> groups,
    int maxFiles,
  ) {
    final List<_FileGroup> sorted = groups.values.toList()
      ..sort((_FileGroup a, _FileGroup b) =>
          b.matches.length.compareTo(a.matches.length));
    final List<_FileGroup> kept =
        sorted.take(math.max(1, maxFiles)).toList()
          ..sort((_FileGroup a, _FileGroup b) =>
              a.matches.first.index.compareTo(b.matches.first.index));
    return kept;
  }

  Set<int> _mandatory(List<_FileGroup> kept) => <int>{
        for (final _FileGroup group in kept) ...<int>{
          group.matches.first.index,
          group.matches.last.index,
          for (final _Match match in group.matches)
            if (match.error) match.index,
        },
      };

  void _fill(List<_FileGroup> kept, Set<int> selected, int maxLines) {
    final List<_Match> candidates = <_Match>[
      for (final _FileGroup group in kept)
        for (final _Match match in group.matches)
          if (!selected.contains(match.index)) match,
    ];
    final int slots = maxLines - selected.length;
    final int count = math.min(math.max(0, slots), candidates.length);
    if (count <= 0) return;
    for (int i = 0; i < count; i++) {
      final double ratio = count == 1 ? 0 : i / (count - 1);
      selected.add(candidates[(ratio * (candidates.length - 1)).round()].index);
    }
  }

  String _render(
    List<_FileGroup> kept,
    Map<String, _FileGroup> groups,
    Set<int> selected,
    int total,
    bool crlf,
  ) {
    final List<String> output = <String>[];
    for (final _FileGroup group in kept) {
      final List<_Match> picked = <_Match>[
        for (final _Match match in group.matches)
          if (selected.contains(match.index)) match,
      ];
      for (final _Match match in picked) {
        output.add(match.line);
      }
      final int hidden = group.matches.length - picked.length;
      if (hidden > 0) output.add('[... $hidden more matches in ${group.path} ...]');
    }
    int droppedFiles = 0;
    int droppedMatches = 0;
    for (final _FileGroup group in groups.values) {
      if (kept.contains(group)) continue;
      droppedFiles++;
      droppedMatches += group.matches.length;
    }
    if (droppedFiles > 0) {
      output.add(
          '[... $droppedFiles more files with $droppedMatches matches ...]');
    }
    return joinTextLines(output, crlf: crlf);
  }
}
