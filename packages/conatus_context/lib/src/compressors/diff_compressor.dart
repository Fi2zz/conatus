/// unified diff 压缩：保全部变更行，只折叠未变更上下文与中间 hunk。
library;

import '../content_compressor.dart';
import '../content_kind.dart';
import '../text_lines.dart';

class _Hunk {
  _Hunk(this.header);

  final String header;
  final List<String> body = <String>[];
}

class _FileDiff {
  final List<String> headers = <String>[];
  final List<_Hunk> hunks = <_Hunk>[];
}

/// diff 压缩器。
class DiffCompressor implements ContentCompressor {
  const DiffCompressor();

  @override
  ContentKind get kind => ContentKind.diff;

  @override
  CompressionDraft? compress(String input, CompressionBudget budget) {
    final List<String> lines = splitTextLines(input);
    final List<_FileDiff> files = _parse(lines);
    final bool crlf = usesCrlf(input);
    final List<String> output = <String>[];
    for (final _FileDiff file in files) {
      output.addAll(_renderFile(file, budget.maxLines, budget.retrievalId));
    }
    if (output.isEmpty) return null;
    final int omitted = lines.length - output.length;
    return CompressionDraft(
      joinTextLines(output, crlf: crlf),
      itemsOmitted: omitted > 0 ? omitted : 0,
      unit: 'lines',
    );
  }

  List<_FileDiff> _parse(List<String> lines) {
    final List<_FileDiff> files = <_FileDiff>[];
    _FileDiff? current;
    for (final String line in lines) {
      if (line.startsWith('diff --git ')) {
        current = _FileDiff();
        files.add(current);
        continue;
      }
      if (current == null) {
        current = _FileDiff();
        files.add(current);
      }
      if (line.startsWith('@@')) {
        current.hunks.add(_Hunk(line));
      } else if (current.hunks.isEmpty) {
        current.headers.add(line);
      } else {
        current.hunks.last.body.add(line);
      }
    }
    files.removeWhere((_FileDiff file) => file.hunks.isEmpty);
    return files;
  }

  List<String> _renderFile(
    _FileDiff file,
    int maxLines,
    String retrievalId,
  ) {
    final List<String> output = <String>[...file.headers];
    for (final _Hunk hunk in file.hunks) {
      output.addAll(_renderHunk(hunk));
    }
    if (output.length <= maxLines || file.hunks.length <= 2) return output;
    final List<_Hunk> hunks = file.hunks;
    final int middle = hunks.length - 2;
    final String suffix =
        retrievalId.isEmpty ? '' : '; context_retrieve id=$retrievalId';
    return <String>[
      ...file.headers,
      ..._renderHunk(hunks.first),
      '[... $middle hunks omitted$suffix ...]',
      ..._renderHunk(hunks.last),
    ];
  }

  List<String> _renderHunk(_Hunk hunk) {
    final List<String> output = <String>[hunk.header];
    final List<String> context = <String>[];
    void flush() {
      if (context.isEmpty) return;
      if (context.length <= 2) {
        output.addAll(context);
      } else {
        output
          ..add(context.first)
          ..add('[... ${context.length - 2} context lines ...]')
          ..add(context.last);
      }
      context.clear();
    }

    for (final String line in hunk.body) {
      if (line.startsWith(' ')) {
        context.add(line);
      } else {
        flush();
        output.add(line);
      }
    }
    flush();
    return output;
  }
}
