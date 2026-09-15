/// conatus TUI 可执行入口。
///
/// ```bash
/// export ARK_API_KEY="..."        # 豆包（首选）
/// export DEEPSEEK_API_KEY="..."   # DeepSeek（备选）
/// dart run conatus_tui --session tui
/// ```
library;

import 'dart:io';

import 'package:conatus_tui/conatus_tui.dart';
import 'package:nocterm/nocterm.dart';

Future<void> main(List<String> args) async {
  final _Options options = _Options.parse(args, stdout);
  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    exaApiKey: Platform.environment['EXA_API_KEY'],
  );
  final ConatusTuiController controller = runtime.createController(
    initialSession: options.session,
    onExit: shutdownApp,
  );
  await runApp(AgentTui(controller: controller, firstInput: options.first));
  await runtime.dispose();
}

/// 命令行选项。
class _Options {
  const _Options({required this.session, this.first});

  /// 启动会话 id。
  final String session;

  /// 挂载后自动发送的首轮输入。
  final String? first;

  static const String _usage = '用法：dart run conatus_tui '
      '[--session <id>] [--first <文本>]\n'
      '  --session <id>   启动会话 id（默认 tui）\n'
      '  --first <文本>   挂载后自动发一轮\n';

  static _Options parse(List<String> args, IOSink out) {
    String session = 'tui';
    String? first;
    for (int i = 0; i < args.length; i++) {
      final String arg = args[i];
      if (arg == '--help' || arg == '-h') {
        out.write(_usage);
        exit(0);
      } else if (arg == '--session' && i + 1 < args.length) {
        session = args[++i];
      } else if (arg == '--first' && i + 1 < args.length) {
        first = args[++i];
      }
    }
    return _Options(session: session, first: first);
  }
}
