/// conatus 的 nocterm 文本 TUI：会话控制器、斜杠命令、会话选择面板与渲染组件。
///
/// 用 [ConatusTuiRuntime] 装配好 conatus 服务后，把 [ConatusTuiController] 交给
/// [AgentTui] 渲染，即可得到一个可直接运行的对话式终端界面。
library;

export 'src/team_snapshot.dart';
export 'src/team_subscription.dart';
export 'src/team_views.dart';
export 'src/transcript.dart';
export 'src/tui.dart';
export 'src/tui_app.dart';
export 'src/tui_chrome.dart';
export 'src/tui_command_menu_view.dart';
export 'src/tui_commands.dart';
export 'src/tui_controller.dart' show ConatusTuiController, isValidSessionId;
export 'src/tui_help.dart';
export 'src/tui_message.dart';
export 'src/tui_session_picker.dart';
export 'src/tui_session_picker_view.dart';
export 'src/tui_views.dart';
export 'src/voice_reporter.dart';
