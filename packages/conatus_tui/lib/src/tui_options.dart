/// conatus TUI 入口的命令行选项：解析 `--session` / `--first` / `--help`。
///
/// 从 `bin/conatus_tui.dart` 提出来，调用方（自己的 `main` 或别的入口）因此能
/// 复用同一套解析与用法文案，不必再抄一遍。
library;

/// 缺省启动会话 id。
const String kTuiDefaultSession = 'tui';

/// 命令行选项。
class TuiOptions {
  /// 构造选项。
  const TuiOptions({
    this.session = kTuiDefaultSession,
    this.first,
    this.helpRequested = false,
  });

  /// 启动会话 id。
  final String session;

  /// 挂载后自动发送的首轮输入；`null` 表示不发。
  final String? first;

  /// 命令行里是否出现了 `--help` / `-h`。
  ///
  /// 解析本身不打印也不退出，由调用方决定怎么处理。
  final bool helpRequested;

  /// 用法文案。
  static const String usage = '用法：dart run conatus_tui '
      '[--session <id>] [--first <文本>]\n'
      '  --session <id>   启动会话 id（默认 tui）\n'
      '  --first <文本>   挂载后自动发一轮\n';

  /// 解析命令行参数。
  ///
  /// 未知参数忽略；`--session` / `--first` 缺后续值时按未出现处理。
  static TuiOptions parse(List<String> args) {
    String session = kTuiDefaultSession;
    String? first;
    bool helpRequested = false;
    for (int index = 0; index < args.length; index++) {
      final String arg = args[index];
      if (arg == '--help' || arg == '-h') {
        helpRequested = true;
      } else if (arg == '--session' && index + 1 < args.length) {
        session = args[++index];
      } else if (arg == '--first' && index + 1 < args.length) {
        first = args[++index];
      }
    }
    return TuiOptions(
      session: session,
      first: first,
      helpRequested: helpRequested,
    );
  }
}
