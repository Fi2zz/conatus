/// 纯文本压缩：折叠重复、保留高信息行，其余等距采样。
library;

import 'dart:math' as math;

import '../content_compressor.dart';
import '../content_kind.dart';
import '../text_lines.dart';

final RegExp _anchor = RegExp(
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
  r'|\b[0-9a-fA-F]{8,}\b'
  r'|https?://'
  r'|(?:^|\s)(?:/|\./|\.\./|[A-Za-z]:\\)\S+'
  r'|\b(error|fatal|fail|exception|timeout|denied|panic|stack)\b',
  caseSensitive: false,
);

/// 纯文本压缩器。
class TextCompressor implements ContentCompressor {
  const TextCompressor();

  @override
  ContentKind get kind => ContentKind.text;

  @override
  CompressionDraft? compress(String input, CompressionBudget budget) {
    final List<String> lines = splitTextLines(input);
    if (lines.length < 10) return null;
    final List<String> deduped = _dedupe(lines);
    final Set<int> keep = _select(deduped, budget.targetRatio);
    if (keep.length >= lines.length) return null;
    final String output = _render(deduped, keep, usesCrlf(input));
    if (output.length > input.length * 0.85) return null;
    return CompressionDraft(
      output,
      itemsOmitted: lines.length - keep.length,
      unit: 'lines',
    );
  }

  List<String> _dedupe(List<String> lines) {
    final List<String> output = <String>[];
    int index = 0;
    while (index < lines.length) {
      final String line = lines[index];
      int run = 1;
      while (index + run < lines.length && lines[index + run] == line) {
        run++;
      }
      if (line.trim().isEmpty) {
        output.addAll(List<String>.filled(run >= 3 ? 1 : run, ''));
      } else if (run > 1) {
        output.add('$line  (×$run)');
      } else {
        output.add(line);
      }
      index += run;
    }
    return output;
  }

  Set<int> _select(List<String> lines, double ratio) {
    final Set<int> keep = <int>{
      for (int i = 0; i < math.min(10, lines.length); i++) i,
      for (int i = math.max(0, lines.length - 10); i < lines.length; i++) i,
      for (int i = 0; i < lines.length; i++)
        if (_anchor.hasMatch(lines[i])) i,
    };
    final int target = math.max(keep.length, (lines.length * ratio).round());
    final List<int> middle = <int>[
      for (int i = 0; i < lines.length; i++)
        if (!keep.contains(i)) i,
    ];
    final int slots = target - keep.length;
    if (slots <= 0 || middle.isEmpty) return keep;
    final int count = math.min(slots, middle.length);
    for (int i = 0; i < count; i++) {
      final double step = count == 1 ? 0 : i / (count - 1);
      keep.add(middle[(step * (middle.length - 1)).round()]);
    }
    return keep;
  }

  String _render(List<String> lines, Set<int> keep, bool crlf) {
    final List<int> indices = keep.toList()..sort();
    final List<String> output = <String>[];
    int previous = -1;
    for (final int index in indices) {
      final int gap = index - previous - 1;
      if (gap > 0) output.add('[... $gap lines omitted ...]');
      output.add(lines[index]);
      previous = index;
    }
    final int tail = lines.length - previous - 1;
    if (tail > 0) output.add('[... $tail lines omitted ...]');
    return joinTextLines(output, crlf: crlf);
  }
}
