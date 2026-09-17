/// TUI 斜杠命令表与 `/` 命令菜单状态：前缀过滤、光标移动、取选中项。
library;

/// 一条斜杠命令；[argHint] 非空表示需要参数（如 `/session <id>`）。
class TuiCommand {
  const TuiCommand({
    required this.name,
    required this.description,
    this.argHint,
  });

  /// 命令名（不含前导 `/`）。
  final String name;

  /// 帮助文案里的说明。
  final String description;

  /// 参数提示；非空表示该命令需要参数。
  final String? argHint;

  /// 是否需要参数。
  bool get takesArgs => argHint != null;

  /// 输入框补全用的命令词：`/session`。
  String get token => '/$name';

  /// 帮助文案里的完整用法：`/session <id>`。
  String get usage => takesArgs ? '/$name $argHint' : '/$name';
}

/// TUI 支持的全部斜杠命令（帮助文案与 `/` 菜单共用同一份数据）。
const List<TuiCommand> tuiCommands = <TuiCommand>[
  TuiCommand(name: 'help', description: '显示本帮助'),
  TuiCommand(name: 'new', description: '开启新会话（上一会话已保存）'),
  TuiCommand(
    name: 'session',
    description: '切换或新建会话（id 即数据文件名）',
    argHint: '<id>',
  ),
  TuiCommand(name: 'sessions', description: '打开会话选择面板（↑↓ 选择，Enter 切换）'),
  TuiCommand(name: 'tools', description: '列出当前已注册的工具'),
  TuiCommand(
    name: 'plan',
    description: '进入 / 退出 Plan Mode（先规划，经 exit_plan_mode 提交后执行）',
  ),
  TuiCommand(
    name: 'goal',
    description: '管理长期目标（status / set / edit / pause / resume / done / clear）',
    argHint: '<子命令>',
  ),
  TuiCommand(
    name: 'remember',
    description: '直接记住一段信息（不经模型）',
    argHint: '<内容>',
  ),
  TuiCommand(
    name: 'forget',
    description: '直接遗忘记忆（不经模型）',
    argHint: '<id 或 关键字>',
  ),
  TuiCommand(name: 'telemetry', description: '显示最近的可观测性事件'),
  TuiCommand(name: 'clear', description: '清空屏上记录（不改动会话数据）'),
  TuiCommand(name: 'exit', description: '退出并关闭 TUI（同 /quit、Ctrl+C）'),
];

/// `/` 命令菜单状态：输入以 `/` 开头且命令词未带参时打开，用前缀过滤命令表。
class TuiCommandMenu {
  bool _open = false;
  String _query = '';
  List<TuiCommand> _matches = const <TuiCommand>[];
  int _index = 0;

  /// 面板是否可见（有匹配才显示）。
  bool get open => _open && _matches.isNotEmpty;

  /// 当前查询词。
  String get query => _query;

  /// 匹配到的命令。
  List<TuiCommand> get matches => _matches;

  /// 当前选中项下标。
  int get index => _index;

  /// 当前选中命令；无匹配返回 `null`。
  TuiCommand? get selected => _matches.isEmpty ? null : _matches[_index];

  /// 跟随输入框文本：`/` 开头且未出现空白时打开并按前缀过滤，否则关闭。
  void syncInput(String text) {
    final bool typingCommand =
        text.startsWith('/') && !text.contains(RegExp(r'\s'));
    if (!typingCommand) {
      _reset();
      return;
    }
    final String query = text.substring(1);
    _query = query;
    _matches = <TuiCommand>[
      for (final TuiCommand command in tuiCommands)
        if (command.name.startsWith(query)) command,
    ];
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

  /// 关闭面板。
  void close() => _reset();

  void _reset() {
    _open = false;
    _query = '';
    _matches = const <TuiCommand>[];
    _index = 0;
  }
}
