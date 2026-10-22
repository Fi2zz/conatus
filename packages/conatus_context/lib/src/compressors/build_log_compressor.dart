/// 构建/测试日志压缩：保错误、栈与摘要，丢弃重复流水线。
library;

import '../content_compressor.dart';
import '../content_kind.dart';
import '../text_lines.dart';

final RegExp _levelPattern = RegExp(
  r'\b(FATAL|ERROR|ERR|FAIL(?:ED|URE)?|WARNING|WARN|INFO|DEBUG|TRACE)\b',
  caseSensitive: false,
);
final RegExp _summaryPattern = RegExp(
  r'(\d+ (?:passed|failed|errors?)|^Tests?:|BUILD (?:SUCCESS|FAILED)|'
  r'make: \*\*\*)',
);
final RegExp _stackFrame = RegExp(r'^\s+(?:File "|at |\.\.\. )');
final RegExp _stackBar = RegExp(r'^\s+\|');

class _Selection {
  const _Selection(this.indices, this.omitted);

  final Set<int> indices;
  final int omitted;
}

/// 构建/测试日志压缩器。
class BuildLogCompressor implements ContentCompressor {
  const BuildLogCompressor();

  @override
  ContentKind get kind => ContentKind.buildLog;

  @override
  CompressionDraft? compress(String input, CompressionBudget budget) {
    final List<String> lines = splitTextLines(input);
    if (lines.length < 10) return null;
    final _Selection? selection = _select(lines, budget);
    if (selection == null) return null;
    return CompressionDraft(
      _render(lines, selection.indices, selection.omitted, usesCrlf(input)),
      itemsOmitted: selection.omitted,
      unit: 'lines',
    );
  }

  _Selection? _select(List<String> lines, CompressionBudget budget) {
    final Set<int> errors = <int>{};
    final Set<int> stacks = <int>{};
    final Set<int> summaries = <int>{};
    for (int i = 0; i < lines.length; i++) {
      final String? level = _level(lines[i]);
      if (level == 'ERROR' || level == 'FATAL' || level == 'FAIL') {
        errors.add(i);
      }
      if (_isStack(lines[i])) stacks.add(i);
      if (_summaryPattern.hasMatch(lines[i])) summaries.add(i);
    }
    final Set<int> warnings = _dedupedWarnings(lines);
    final Set<int> droppedWarnings = <int>{
      for (int i = 0; i < lines.length; i++)
        if (_level(lines[i]) == 'WARN' && !warnings.contains(i)) i,
    };
    final Set<int> keep = <int>{
      ...errors,
      ...stacks,
      ...summaries,
      if (!budget.conservative) ...warnings,
    };
    if (keep.isEmpty) return null;
    final int maxLines =
        budget.conservative ? budget.maxLines ~/ 2 : budget.maxLines;
    final Set<int> selected = _withContext(
      lines.length,
      keep,
      <int>{...errors, ...stacks, ...summaries},
      maxLines,
      budget.conservative ? 1 : 2,
    )..removeAll(droppedWarnings);
    return _Selection(selected, lines.length - selected.length);
  }

  Set<int> _dedupedWarnings(List<String> lines) {
    final Set<String> seen = <String>{};
    final Set<int> indices = <int>{};
    for (int i = 0; i < lines.length; i++) {
      if (_level(lines[i]) != 'WARN') continue;
      if (seen.add(_messagePrefix(lines[i]))) indices.add(i);
    }
    return indices;
  }

  Set<int> _withContext(
    int length,
    Set<int> keep,
    Set<int> seeds,
    int maxLines,
    int context,
  ) {
    final Set<int> selected = <int>{...keep};
    for (int distance = 1; distance <= context; distance++) {
      for (final int seed in seeds) {
        if (selected.length >= maxLines) break;
        for (final int candidate in <int>[seed - distance, seed + distance]) {
          if (candidate >= 0 && candidate < length) selected.add(candidate);
        }
      }
      if (selected.length >= maxLines) break;
    }
    return selected;
  }

  String _render(
    List<String> lines,
    Set<int> selected,
    int omitted,
    bool crlf,
  ) {
    final List<int> indices = selected.toList()..sort();
    final List<String> output = <String>[];
    int previous = -1;
    for (final int index in indices) {
      final int gap = index - previous - 1;
      if (gap > 0) output.add('[... $gap lines omitted ...]');
      output.add(lines[index]);
      previous = index;
    }
    final int tailGap = lines.length - previous - 1;
    if (tailGap > 0) output.add('[... $tailGap lines omitted ...]');
    return joinTextLines(output, crlf: crlf);
  }

  String? _level(String line) {
    final RegExpMatch? match = _levelPattern.firstMatch(line);
    if (match == null) return null;
    final String level = match.group(1)!.toUpperCase();
    if (level.startsWith('FAIL')) return 'FAIL';
    if (level == 'ERR') return 'ERROR';
    return level;
  }

  bool _isStack(String line) =>
      line.contains('Traceback (most recent call last)') ||
      _stackFrame.hasMatch(line) ||
      _stackBar.hasMatch(line) ||
      line.startsWith('-->');

  String _messagePrefix(String line) {
    final int colon = line.indexOf(':');
    final int equal = line.indexOf('=');
    final List<int> cuts = <int>[
      if (colon >= 0) colon,
      if (equal >= 0) equal,
    ];
    if (cuts.isEmpty) return line.trim();
    cuts.sort();
    return line.substring(0, cuts.first).trim();
  }
}
