/// @ 文件补全菜单状态：输入框光标前的 `@<前缀>` 触发，列举匹配的文件 / 目录。
///
/// 只做状态与候选列举（同步 `dart:io`，cwd 可注入以便测试）；按键与渲染由
/// 根组件和 [AtRefMenuView] 负责。补全插入 `@<路径>`，发送时再由
/// [expandAtRefs] 展开为 `<file>` 块。
library;

import 'dart:io';

/// 一个补全候选。
class AtRefCandidate {
  const AtRefCandidate({required this.path, required this.isDir});

  /// 相对 cwd 的补全路径；目录以 `/` 结尾。
  final String path;

  /// 是否目录（补全后继续列举子项）。
  final bool isDir;

  /// 列表右列展示的名字（末段，目录不带尾 `/`）。
  String get name {
    final String trimmed =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final int slash = trimmed.lastIndexOf('/');
    return slash < 0 ? trimmed : trimmed.substring(slash + 1);
  }
}

/// `@` 文件补全菜单状态。
class AtRefMenu {
  /// 构造菜单；[cwd] 每次列举时提供基准目录，[maxMatches] 限制候选数量。
  AtRefMenu({required String Function() cwd, this.maxMatches = 20})
      : _cwd = cwd;

  final String Function() _cwd;

  /// 最多展示的候选数。
  final int maxMatches;

  bool _open = false;
  int _tokenStart = 0;
  String _query = '';
  List<AtRefCandidate> _matches = const <AtRefCandidate>[];
  int _index = 0;

  /// 面板是否可见（有匹配才显示）。
  bool get open => _open && _matches.isNotEmpty;

  /// 当前 `@` 之后的前缀词。
  String get query => _query;

  /// 匹配到的候选。
  List<AtRefCandidate> get matches => _matches;

  /// 当前选中项下标。
  int get index => _index;

  /// 当前选中候选；无匹配返回 `null`。
  AtRefCandidate? get selected => _matches.isEmpty ? null : _matches[_index];

  /// 跟随输入框文本与光标：光标前是 `@<前缀>` 时打开并列举，否则关闭。
  ///
  /// [cursor] 越界时按文本末尾处理。
  void syncInput(String text, {required int cursor}) {
    final int pos = cursor < 0 || cursor > text.length ? text.length : cursor;
    final int at = _activeAt(text, pos);
    if (at < 0) {
      _reset();
      return;
    }
    _tokenStart = at;
    _query = text.substring(at + 1, pos);
    _matches = _list(_query);
    _index = 0;
    _open = true;
  }

  /// 移动光标（越界钳制；空列表无操作）。
  void move(int delta) {
    if (_matches.isEmpty) {
      return;
    }
    final int next = _index + delta;
    _index =
        next < 0 ? 0 : (next >= _matches.length ? _matches.length - 1 : next);
  }

  /// 补全：把 `@<前缀>` 换成选中路径；返回 (新文本, 新光标)；无选中返回 null。
  ///
  /// 目录补全后光标停在路径末尾（菜单继续列举子项），文件补全后追加空格
  /// 结束引用。
  (String, int)? complete(String text, {required int cursor}) {
    final AtRefCandidate? candidate = selected;
    if (candidate == null) {
      return null;
    }
    final String replacement =
        candidate.isDir ? '@${candidate.path}' : '@${candidate.path} ';
    return (
      text.replaceRange(_tokenStart, cursor, replacement),
      _tokenStart + replacement.length,
    );
  }

  /// 关闭面板。
  void close() => _reset();

  void _reset() {
    _open = false;
    _query = '';
    _matches = const <AtRefCandidate>[];
    _index = 0;
  }

  /// 光标前最近的触发 `@` 下标（`@` 前是行首或空白，且到光标无空白）；无则 -1。
  int _activeAt(String text, int cursor) {
    for (int i = cursor - 1; i >= 0; i--) {
      final String ch = text[i];
      if (ch == '@') {
        return i == 0 || _isSpace(text[i - 1]) ? i : -1;
      }
      if (_isSpace(ch)) {
        return -1;
      }
    }
    return -1;
  }

  /// 按 [query] 列举：`lib/re` → `<cwd>/lib` 下以 `re` 开头的条目。
  List<AtRefCandidate> _list(String query) {
    final int slash = query.lastIndexOf('/');
    final String dirPart = slash < 0 ? '' : query.substring(0, slash + 1);
    final String prefix = slash < 0 ? query : query.substring(slash + 1);
    final Directory dir = Directory('${_cwd()}${Platform.pathSeparator}$dirPart');
    if (!dir.existsSync()) {
      return const <AtRefCandidate>[];
    }
    final List<AtRefCandidate> found = <AtRefCandidate>[];
    for (final FileSystemEntity entity in dir.listSync()) {
      final String name = entity.path.split(Platform.pathSeparator).last;
      if (name.startsWith('.') || !name.startsWith(prefix)) {
        continue;
      }
      final bool isDir = entity is Directory;
      found.add(AtRefCandidate(
        path: '$dirPart$name${isDir ? '/' : ''}',
        isDir: isDir,
      ));
    }
    found.sort((AtRefCandidate a, AtRefCandidate b) {
      if (a.isDir != b.isDir) {
        return a.isDir ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    return found.length > maxMatches ? found.sublist(0, maxMatches) : found;
  }

  static bool _isSpace(String ch) => RegExp(r'\s').hasMatch(ch);
}
