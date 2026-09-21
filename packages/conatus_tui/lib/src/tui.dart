/// nocterm TUI 主界面：顶栏 + 对话记录 + 输入栏 + 状态栏，斜杠命令见 `/help`。
///
/// 状态与命令由 [ConatusTuiController] 持有；本组件只做渲染与按键分派。
library;

import 'dart:async';
import 'dart:io';

import 'package:nocterm/nocterm.dart';

import 'at_ref_menu.dart';
import 'at_ref_menu_view.dart';
import 'team_snapshot.dart';
import 'team_views.dart';
import 'tui_choice.dart';
import 'tui_choice_view.dart';
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
  late final TuiCommandMenu _menu =
      TuiCommandMenu(commands: () => _controller.commands);
  late final AtRefMenu _atMenu =
      AtRefMenu(cwd: () => Directory.current.path);
  Timer? _spin;
  Timer? _exitTimer;
  int _tick = 0;
  bool _exiting = false;
  bool _confirmExit = false;
  ViewMode _view = ViewMode.chat;
  String _selectedText = '';
  int _selectionEpoch = 0;

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

  /// 输入变化：同步 `/` 菜单与 `@` 文件补全并重绘。
  void _onInputChanged() {
    _menu.syncInput(_input.text);
    final int cursor = _input.selection.baseOffset;
    _atMenu.syncInput(
      _input.text,
      cursor: cursor < 0 ? _input.text.length : cursor,
    );
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

  /// 输入框按键拦截：`/` 菜单打开时用 ↑↓ 选择、Enter 运行、Tab 补全；
  /// Esc 一律返回 false 冒泡，由根组件 `_onKey` 统一处理（关闭面板/视图、打断轮次）。
  /// Ctrl+T 视图切换、Ctrl+C/Alt+C 复制/打断/退出，先于文本域消费。
  bool _onInputKey(KeyboardEvent event) {
    if (event.matches(LogicalKey.keyT, ctrl: true)) {
      _toggleView();
      return true;
    }
    if (_onCopyKey(event)) {
      return true;
    }
    if (_onChoiceKey(event)) {
      return true;
    }
    if (_onAtMenuKey(event)) {
      return true;
    }
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

  /// `@` 文件补全按键：↑↓ 移动、Tab/Enter 补全、Esc 关闭；未打开返回 false。
  bool _onAtMenuKey(KeyboardEvent event) {
    if (!_atMenu.open) {
      return false;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      _atMenu.move(-1);
    } else if (event.logicalKey == LogicalKey.arrowDown) {
      _atMenu.move(1);
    } else if (event.logicalKey == LogicalKey.tab ||
        event.logicalKey == LogicalKey.enter) {
      _completeAtRef();
      return true;
    } else if (event.logicalKey == LogicalKey.escape) {
      _atMenu.close();
    } else {
      return false; // 其余按键交给输入框（继续打字）。
    }
    _refresh();
    return true;
  }

  /// 把选中候选补进输入框：目录停在路径末尾（继续列举），文件追加空格收尾。
  void _completeAtRef() {
    final (String, int)? result =
        _atMenu.complete(_input.text, cursor: _input.selection.baseOffset);
    if (result == null) {
      return;
    }
    final (String text, int cursor) = result;
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: cursor);
    _atMenu.syncInput(text, cursor: cursor);
    _refresh();
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

  /// 选项浮层按键：↑↓ 移动、Enter 确认、Esc 取消；浮层未打开返回 false。
  bool _onChoiceKey(KeyboardEvent event) {
    final TuiChoicePrompt prompt = _controller.choice;
    if (!prompt.open) {
      return false;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      prompt.move(-1);
    } else if (event.logicalKey == LogicalKey.arrowDown) {
      prompt.move(1);
    } else if (event.logicalKey == LogicalKey.enter) {
      prompt.confirm();
    } else if (event.logicalKey == LogicalKey.escape) {
      prompt.cancel();
    }
    return true; // 浮层打开时吞掉按键，避免误输入。
  }

  /// Ctrl+C / Alt+C：平台差异化按键语义。
  ///
  /// 输入框有内容时 Ctrl+C 恒为清空输入（shell 习惯）。
  /// macOS：Ctrl+C 忙时打断在飞轮次、空闲连按两次退出；复制走 Alt+C
  /// （Option+C）。其他平台：Ctrl+C 有选中文本时复制，否则连按两次退出。
  /// Alt+C 无选区也吞掉，避免 Option+C 被当作字符输入。
  bool _onCopyKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.keyC && event.isControlPressed) {
      if (_input.text.isNotEmpty) {
        _input.clear();
        return true;
      }
      if (!Platform.isMacOS &&
          !_controller.choice.open &&
          !_controller.picker.open &&
          _copySelection()) {
        return true;
      }
      if (Platform.isMacOS && _controller.busy) {
        _controller.interrupt();
        return true;
      }
      _confirmExitChord();
      return true;
    }
    if (Platform.isMacOS &&
        event.logicalKey == LogicalKey.keyC &&
        event.isAltPressed) {
      if (!_controller.choice.open &&
          !_controller.picker.open &&
          _copySelection()) {
        return true;
      }
      return true;
    }
    return false;
  }

  bool _onKey(KeyboardEvent event) {
    // Ctrl+T 切换对话/团队视图（兜底：输入框聚焦时由 _onInputKey 先行处理）。
    if (event.matches(LogicalKey.keyT, ctrl: true)) {
      _toggleView();
      return true;
    }
    // Ctrl+C / Alt+C：平台差异化语义，见 _onCopyKey。
    if (_onCopyKey(event)) {
      return true;
    }
    if (_onChoiceKey(event)) {
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
    // Esc 兜底（choice/picker 的 Esc 已在上方处理）：关闭菜单、关闭帮助弹出、
    // 团队视图返回，无面板时打断在飞轮次（busy 时输入框 readOnly 不经
    // _onInputKey，靠这里兜底）。
    if (event.logicalKey == LogicalKey.escape) {
      if (_menu.open) {
        _menu.close();
        _refresh();
        return true;
      }
      if (_atMenu.open) {
        _atMenu.close();
        _refresh();
        return true;
      }
      if (_controller.transcript.closeHelp()) {
        _refresh();
        return true;
      }
      if (_view == ViewMode.team) {
        _toggleView();
        return true;
      }
      _controller.interrupt();
      return true;
    }
    return false;
  }

  /// 复制当前选中文本：消息区选区优先，其次输入框选区；无选区返回 false。
  bool _copySelection() {
    final String text = _selectedText.isNotEmpty
        ? _selectedText
        : _selectedInputText();
    if (text.isEmpty) {
      return false;
    }
    ClipboardManager.copy(text);
    _clearSelection();
    return true;
  }

  /// 输入框内选中文本；无选区返回空串。
  String _selectedInputText() {
    final TextSelection selection = _input.selection;
    if (selection.isCollapsed) {
      return '';
    }
    return _input.text.substring(selection.start, selection.end);
  }

  /// 复制后清除消息区与输入框选区：重建 SelectionArea 以撤销消息区高亮。
  void _clearSelection() {
    _selectedText = '';
    if (!_input.selection.isCollapsed) {
      _input.selection =
          TextSelection.collapsed(offset: _input.selection.extentOffset);
    }
    setState(() => _selectionEpoch++);
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

  /// 切换对话 / 团队视图。
  void _toggleView() {
    setState(() {
      _view = _view == ViewMode.chat ? ViewMode.team : ViewMode.chat;
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
          Expanded(
            child: _view == ViewMode.chat
                ? _body()
                : TeamView(snapshot: _controller.teamSnapshot),
          ),
          if (_menu.open)
            TuiCommandMenuView(matches: _menu.matches, selected: _menu.index),
          if (_atMenu.open)
            AtRefMenuView(matches: _atMenu.matches, selected: _atMenu.index),
          TeamStatusBar(snapshot: _controller.teamSnapshot),
          TuiInputBar(
            controller: _input,
            focused: !_controller.picker.open && !_controller.choice.open,
            busy: _controller.busy,
            onSubmitted: (_) => _submit(),
            onKeyEvent: _onInputKey,
          ),
          TuiStatusBar(
            pickerOpen: _controller.picker.open,
            busy: _controller.busy,
            tick: _tick,
            menuOpen: _menu.open,
            choiceOpen: _controller.choice.open,
            exitPending: _confirmExit,
            permissionLabel: _controller.permissionLabel,
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
    if (_controller.choice.open) {
      final TuiChoiceRequest? request = _controller.choice.request;
      if (request != null) {
        return TuiChoiceView(
          request: request,
          selected: _controller.choice.index,
        );
      }
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
    final child = Scrollbar(
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
    // key 变化时重建，用于复制后撤销鼠标选区（nocterm 无公开清除 API）。
    return SelectionArea(
      key: ValueKey<int>(_selectionEpoch),
      onSelectionChanged: (String text) => _selectedText = text,
      child: child,
    );
  }
}
