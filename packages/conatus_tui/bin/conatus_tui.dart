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

Future<void> main(List<String> args) async {
  final TuiOptions options = TuiOptions.parse(args);
  if (options.helpRequested) {
    stdout.write(TuiOptions.usage);
    return;
  }
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
