/// DeepSeek 文本 TUI Demo。
///
/// 用 conatus 的 `DeepSeekProvider` 驱动 [AgentTui]；未设置 `DEEPSEEK_API_KEY`
/// 时退回一个离线脚本模型，便于无 Key 预览界面（时间类问题仍会走 `get_time` 工具）。
///
/// ```bash
/// # 真实调用 DeepSeek
/// export DEEPSEEK_API_KEY="sk-..."
/// dart run packages/conatus_tui/example/deepseek_demo.dart
///
/// # 指定模型 / 会话 / 首轮
/// dart run packages/conatus_tui/example/deepseek_demo.dart \
///   --model deepseek-chat --session demo --first "现在几点？"
/// ```
library;

import 'dart:io';

import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:nocterm/nocterm.dart';

Future<void> main(List<String> args) async {
  final _Options options = _Options.parse(args, stdout);
  final String key = Platform.environment['DEEPSEEK_API_KEY'] ?? '';
  final bool configured = key.trim().isNotEmpty;

  final FallbackLlm llm = configured
      ? FallbackLlm(<LlmProvider>[DeepSeekProvider(model: options.model)])
      : FallbackLlm(<LlmProvider>[_OfflineProvider()]);
  final String label = configured
      ? (options.model ?? 'deepseek-flash')
      : '离线 Demo（未设置 DEEPSEEK_API_KEY）';

  if (!configured) {
    stdout.writeln('未检测到 DEEPSEEK_API_KEY：以离线脚本模型运行 Demo。');
    stdout.writeln('设置 DEEPSEEK_API_KEY 后重跑即可接入真实 DeepSeek。');
  }

  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    llm: llm,
    modelLabel: label,
  );
  final ConatusTuiController controller = runtime.createController(
    initialSession: options.session,
    onExit: shutdownApp,
    name: 'DeepSeek Demo',
  );
  await runApp(AgentTui(controller: controller, firstInput: options.first));
  await runtime.dispose();
}

/// 命令行选项。
class _Options {
  const _Options({required this.session, this.model, this.first});

  /// 启动会话 id。
  final String session;

  /// DeepSeek 模型名（缺省用 provider 默认值）。
  final String? model;

  /// 挂载后自动发送的首轮输入。
  final String? first;

  static const String _usage = '用法：dart run example/deepseek_demo.dart '
      '[--session <id>] [--model <name>] [--first <文本>]\n'
      '  --session <id>   启动会话 id（默认 deepseek）\n'
      '  --model <name>   DeepSeek 模型名（默认 deepseek-flash）\n'
      '  --first <文本>   挂载后自动发一轮\n';

  static _Options parse(List<String> args, IOSink out) {
    String session = 'deepseek';
    String? model;
    String? first;
    for (int i = 0; i < args.length; i++) {
      final String arg = args[i];
      if (arg == '--help' || arg == '-h') {
        out.write(_usage);
        exit(0);
      } else if (arg == '--session' && i + 1 < args.length) {
        session = args[++i];
      } else if (arg == '--model' && i + 1 < args.length) {
        model = args[++i];
      } else if (arg == '--first' && i + 1 < args.length) {
        first = args[++i];
      }
    }
    return _Options(session: session, model: model, first: first);
  }
}

/// 无 Key 时的离线脚本模型：时间类问题回一次 `get_time` 工具调用，其余直接回显。
class _OfflineProvider implements LlmProvider {
  @override
  String get name => 'offline';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    final String user = _lastUser(messages);
    final bool timeToolUsed = messages.any((LlmMessage m) => m.role == 'tool');
    if (!timeToolUsed && _asksTime(user)) {
      return const LlmResult(
        content: '',
        provider: 'offline',
        model: 'scripted',
        toolCalls: <LlmToolCall>[
          LlmToolCall(id: 'offline-1', name: 'get_time'),
        ],
      );
    }
    return LlmResult(
      content: '（离线 Demo）未接入真实模型。你说的是：「$user」。\n'
          '设置 DEEPSEEK_API_KEY 后重跑即可与 DeepSeek 对话。',
      provider: 'offline',
      model: 'scripted',
    );
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}

  static bool _asksTime(String text) =>
      text.contains('时间') ||
      text.contains('几点') ||
      text.toLowerCase().contains('time');

  static String _lastUser(List<LlmMessage> messages) {
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'user') {
        return messages[i].content;
      }
    }
    return '';
  }
}
