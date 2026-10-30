/// 统一格式 diff 的逐行状态机：把文本收口成 [FileDiff] 列表。
///
/// 与 `diff_parser.dart` 分开只为守住单文件行数约束；对外只经
/// `parseUnifiedDiff` 暴露。
library;

import 'diff_model.dart';
import 'diff_paths.dart';
import 'diff_types.dart';

final RegExp _hunkHeader = RegExp(
  r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@',
);
final RegExp _binaryHint = RegExp(
  r'^(Binary files .* differ|GIT binary patch)$',
);

/// 逐行构建当前文件，遇到下一个文件头时收口。
class UnifiedDiffBuilder {
  final List<FileDiff> _files = <FileDiff>[];
  final _HunkCursor _cursor = _HunkCursor();
  String? _oldPath;
  String? _newPath;
  bool _newFile = false;
  bool _deletedFile = false;
  bool _renamed = false;
  bool _fromGitHeader = false;

  /// 喂入一行（不含 `\n`）。结构行容忍尾随 `\r`；hunk 内容行**保留**
  /// `\r`——CRLF 文件的内容就带它，剥掉会让 `apply_patch` 的上下文失配。
  // REASON: 逐行状态机解析是既定实现，else-if 链即解析分支本身。
  void add(String raw) {
    final String line =
        raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (_cursor.active) {
      _cursor.add(raw);
    } else if (line.startsWith('diff --git ')) {
      _startGitHeader(line);
    } else if (line.startsWith('new file mode ')) {
      _newFile = true;
    } else if (line.startsWith('deleted file mode ')) {
      _deletedFile = true;
    } else if (line.startsWith('rename from ') ||
        line.startsWith('rename to ')) {
      _renamed = true;
    } else if (line.startsWith('--- ')) {
      final bool headerPending = _oldPath != null && !_fromGitHeader;
      if (_cursor.started || headerPending) _flush();
      _oldPath = cleanDiffPath(line.substring(4));
    } else if (line.startsWith('+++ ')) {
      _newPath = cleanDiffPath(line.substring(4));
    } else if (_binaryHint.hasMatch(line)) {
      _cursor.markBinary();
    } else if (line.startsWith('@@ ')) {
      _cursor.start(line);
    } else {
      _cursor.add(raw);
    }
  }

  /// 收口当前文件并返回全部结果。
  List<FileDiff> finish() {
    _flush();
    return List<FileDiff>.unmodifiable(_files);
  }

  void _startGitHeader(String raw) {
    _flush();
    _fromGitHeader = true;
    final List<String> paths = gitDiffPaths(
      raw.substring('diff --git '.length).trim(),
    );
    if (paths.length < 2) return;
    _oldPath = cleanDiffPath(paths[0]);
    _newPath = cleanDiffPath(paths[1]);
  }

  void _flush() {
    final bool headerless = _oldPath == null && _newPath == null;
    if (headerless && !_cursor.started) {
      _reset();
      return;
    }
    final String path = _path();
    if (path.isEmpty) {
      _reset();
      return;
    }
    _files.add(
      FileDiff(
        path: path,
        status: _status(),
        hunks: _cursor.result,
        additions: _cursor.additions,
        deletions: _cursor.deletions,
      ),
    );
    _reset();
  }

  void _reset() {
    _cursor.clear();
    _oldPath = null;
    _newPath = null;
    _newFile = false;
    _deletedFile = false;
    _renamed = false;
    _fromGitHeader = false;
  }

  String _path() {
    final String? target =
        _newPath != null && _newPath != '/dev/null' ? _newPath : _oldPath;
    return target ?? '';
  }

  String _status() {
    if (_cursor.binary) return 'binary';
    if (_newFile || _oldPath == '/dev/null') return 'added';
    if (_deletedFile || _newPath == '/dev/null') return 'deleted';
    if (_renamed) return 'renamed';
    return 'modified';
  }
}

/// 当前 hunk 的内容游标：按 `@@` 声明的行数消费内容，避免把以 `--- ` /
/// `+++ ` 开头的内容行误判成文件头。
class _HunkCursor {
  final List<DiffHunk> hunks = <DiffHunk>[];
  DiffHunk? _hunk;
  int _oldLeft = 0;
  int _newLeft = 0;
  int additions = 0;
  int deletions = 0;
  bool binary = false;

  /// hunk 声明的旧 / 新侧行数还没消费完。
  bool get active => _hunk != null && (_oldLeft > 0 || _newLeft > 0);

  /// 是否已有内容（含仅二进制标记的文件）。
  bool get started => hunks.isNotEmpty || binary;

  List<DiffHunk> get result =>
      binary ? const <DiffHunk>[] : List<DiffHunk>.unmodifiable(hunks);

  void start(String raw) {
    if (binary) return;
    final RegExpMatch? match = _hunkHeader.firstMatch(raw);
    if (match == null) return;
    _oldLeft = int.parse(match.group(2) ?? '1');
    _newLeft = int.parse(match.group(4) ?? '1');
    final DiffHunk hunk = DiffHunk(
      oldStart: int.parse(match.group(1)!),
      oldLines: _oldLeft,
      newStart: int.parse(match.group(3)!),
      newLines: _newLeft,
      lines: <String>[],
    );
    hunks.add(hunk);
    _hunk = hunk;
  }

  void add(String raw) {
    final DiffHunk? hunk = _hunk;
    if (hunk == null || raw.isEmpty || raw.startsWith('\\')) return;
    if (raw.contains('\u0000')) {
      markBinary();
      return;
    }
    final String prefix = raw.substring(0, 1);
    if (prefix != ' ' && prefix != '-' && prefix != '+') return;
    if (prefix == '+') additions++;
    if (prefix == '-') deletions++;
    if (prefix != '+' && _oldLeft > 0) _oldLeft--;
    if (prefix != '-' && _newLeft > 0) _newLeft--;
    hunk.lines.add(raw);
  }

  void markBinary() {
    binary = true;
    _hunk = null;
    hunks.clear();
    _oldLeft = 0;
    _newLeft = 0;
  }

  void clear() {
    hunks.clear();
    _hunk = null;
    _oldLeft = 0;
    _newLeft = 0;
    additions = 0;
    deletions = 0;
    binary = false;
  }
}
