/// nocterm TUI 主界面：顶栏 + 对话记录 + 输入栏 + 状态栏，斜杠命令见 `/help`。
///
/// 状态与命令由 [ConatusTuiController] 持有；本组件只做渲染与按键分派。
library;

import 'dart:async';

import 'package:nocterm/nocterm.dart';

import 'tui_chrome.dart';
import 'tui_command_menu_view.dart';
import 'tui_commands.dart';
import 'tui_controller.dart';
import 'tui_message.dart';
import 'tui_session_picker_view.dart';
import 'tui_views.dart';

/// conatus TUI 根组件。
class AgentTui extends StatefulComponent {
  const AgentTui({
    super.key,
    required this.controller,
    this.firstInput,
  });

  /// 会话控制器（含屏上记录与斜杠命令状态）。
  final ConatusTuiController controller;

  /// `--first <文本>`：挂载后自动发一轮，便于冒烟验证。
  final String? firstInput;

  @override
  State<AgentTui> createState() => _AgentTuiState();
}

class _AgentTuiState extends State<AgentTui> {
  late final ConatusTuiController _controller = component.controller;
  final TextEditingController _input = TextEditingController();
  final AutoScrollController _scroll = AutoScrollController();
  final TuiCommandMenu _menu = TuiCommandMenu();
  Timer? _spin;
  Timer? _exitTimer;
  int _tick = 0;
  bool _exiting = false;
  bool _confirmExit = false;

  @override
  void initState() {
    super.initState();
    _controller.onChanged = _refresh;
    _input.addListener(_onInputChanged);
    _spin = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (_controller.busy && mounted) {
        setState(() => _tick++);
      }
    });
    unawaited(_controller.start().then((_) {
      final String? first = component.firstInput;
      if (first != null && first.isNotEmpty) {
        unawaited(_controller.handleLine(first));
      }
    }));
  }

  @override
  void dispose() {
    _spin?.cancel();
    _exitTimer?.cancel();
    _controller
      ..onChanged = null
      ..dispose();
    _input
      ..removeListener(_onInputChanged)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 输入变化：同步 `/` 菜单过滤并重绘。
  void _onInputChanged() {
    _menu.syncInput(_input.text);
    _refresh();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _exit() {
    if (_exiting) {
      return;
    }
    _exiting = true;
    shutdownApp();
  }

  void _submit() {
    final String text = _input.text;
    if (text.trim().isEmpty) {
      return;
    }
    _input.clear();
    unawaited(_controller.handleLine(text));
    setState(() {});
  }

  /// 输入框按键拦截：`/` 菜单打开时用 ↑↓ 选择、Enter 运行、Tab 补全、Esc 关闭。
  bool _onInputKey(KeyboardEvent event) {
    if (!_menu.open) {
      return false;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      _menu.move(-1);
      _refresh();
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowDown) {
      _menu.move(1);
      _refresh();
      return true;
    }
    if (event.logicalKey == LogicalKey.escape) {
      _menu.close();
      _refresh();
      return true;
    }
    if (event.logicalKey == LogicalKey.tab) {
      _completeSelected();
      return true;
    }
    if (event.logicalKey == LogicalKey.enter) {
      _runSelected();
      return true;
    }
    return false;
  }

  /// Tab：把选中命令补全到输入框，不立即执行（带参命令留一个空格）。
  void _completeSelected() {
    final TuiCommand? command = _menu.selected;
    if (command == null) {
      return;
    }
    _input.text = command.takesArgs ? '${command.token} ' : command.token;
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _menu.close(); // 覆盖 setText 触发的自动重开
    _refresh();
  }

  /// Enter：无参命令直接运行；带参命令补全后等用户补参数。
  void _runSelected() {
    final TuiCommand? command = _menu.selected;
    if (command == null) {
      return;
    }
    if (command.takesArgs) {
      _completeSelected();
      return;
    }
    _menu.close();
    _input.clear();
    unawaited(_controller.handleLine(command.token));
    setState(() {});
  }

  bool _onKey(KeyboardEvent event) {
    // Ctrl+C 恒可用：首次提示确认，窗口内再按一次才退出。
    if (event.logicalKey == LogicalKey.keyC && event.isControlPressed) {
      _confirmExitChord();
      return true;
    }
    if (_controller.picker.open) {
      if (event.logicalKey == LogicalKey.arrowUp) {
        _controller.movePicker(-1);
      } else if (event.logicalKey == LogicalKey.arrowDown) {
        _controller.movePicker(1);
      } else if (event.logicalKey == LogicalKey.enter) {
        unawaited(_controller.pickSelected());
      } else if (event.logicalKey == LogicalKey.escape) {
        _controller.closePicker();
      }
      return true; // 面板打开时吞掉按键，避免误输入。
    }
    return false;
  }

  /// Ctrl+C：首次挂起退出确认并计时复位，窗口内再按一次才真正退出。
  void _confirmExitChord() {
    if (_confirmExit) {
      _exit();
      return;
    }
    _exitTimer?.cancel();
    setState(() => _confirmExit = true);
    _exitTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _confirmExit = false);
      }
    });
  }

  @override
  Component build(BuildContext context) {
    return Focusable(
      focused: true,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Component>[
          TuiHeader(
            name: _controller.name,
            sessionId: _controller.sessionId,
            modelLabel: _controller.modelLabel,
          ),
          Expanded(child: _body()),
          if (_menu.open)
            TuiCommandMenuView(matches: _menu.matches, selected: _menu.index),
          TuiInputBar(
            controller: _input,
            focused: !_controller.picker.open,
            busy: _controller.busy,
            onSubmitted: (_) => _submit(),
            onKeyEvent: _onInputKey,
          ),
          TuiStatusBar(
            pickerOpen: _controller.picker.open,
            busy: _controller.busy,
            tick: _tick,
            menuOpen: _menu.open,
            exitPending: _confirmExit,
          ),
        ],
      ),
    );
  }

  Component _body() {
    if (!_controller.ready) {
      return const Center(
        child: Text(
          '正在加载会话…',
          style: TextStyle(color: Colors.gray),
        ),
      );
    }
    if (_controller.picker.open) {
      return SessionPickerView(
        sessions: _controller.picker.list,
        currentId: _controller.sessionId,
        selected: _controller.picker.index,
      );
    }
    final List<TuiMessage> messages = _controller.transcript.messages;
    final bool loading = _controller.busy;
    if (messages.isEmpty && !loading) {
      return const Center(
        child: Text(
          '输入文字开始对话；/help 查看命令。',
          style: TextStyle(color: Colors.gray),
        ),
      );
    }
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(1),
        itemCount: messages.length + (loading ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (index < messages.length) {
            return MessageView(message: messages[index]);
          }
          return LoadingView(tick: _tick);
        },
      ),
    );
  }
}
