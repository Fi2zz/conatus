// Playground Demo：conatus_coding × conatus_tui 组装：TUI 对话 + coding 工具
// （read/write/edit/glob/rg/run_code）+ @ 文件引用（TUI 内置，`@<路径>` 展开
// 进消息）。运行：export ARK_API_KEY="..."（或 DEEPSEEK_API_KEY）；未设置
// Key 时离线脚本模型兜底（发「执行代码」演示 run_code 闭环）。

import 'dart:convert';
import 'dart:io';
import 'package:conatus/conatus.dart';
import 'package:conatus_coding/conatus_coding.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:conatus_tui/conatus_tui.dart';

Future<void> main(List<String> args) async {
  final TuiOptions options = TuiOptions.parse(args);
  if (options.helpRequested) {
    stdout.write(kPlaygroundUsage);
    return;
  }
  final String cwd = parseFlag(args, '--cwd') ?? Directory.current.path;
  final String? model = parseFlag(args, '--model');
  // Key 经凭据服务判断（缺省 EnvCredentials，即环境变量）；provider 内部不再
  // 直接读环境变量。
  final Credentials credentials = EnvCredentials();
  final bool configured = credentials.get('ARK_API_KEY') != null ||
      credentials.get('DEEPSEEK_API_KEY') != null;
  if (!configured) {
    stdout.writeln('未检测到 ARK_API_KEY / DEEPSEEK_API_KEY：以离线脚本模型运行 Demo。');
    stdout.writeln('设置任一 Key 后重跑即可接入真实模型。');
  }
  // 有 Key 时由提供商注册表（`.conatus/providers.json`）的当前 provider 构造
  // LLM（--model 覆盖其默认模型名），/provider 与 /model 命令据此工作。
  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    llm: configured ? null : FallbackLlm(<LlmProvider>[_OfflineProvider()]),
    model: model,
    modelLabel: configured ? null : '离线 Demo',
  );
  final Context app = runtime.app;
  provideCodingForPlayground(app, cwd: cwd);
  app
      .require<SystemPrompt>('systemPrompt')
      .add(kPlaygroundPersona, name: 'playground-persona');
  final ConatusTuiController controller = runtime.createController(
    initialSession: options.session,
    onExit: shutdownApp,
    name: 'Playground',
  );
  await runApp(AgentTui(controller: controller, firstInput: options.first));
  await runtime.dispose();
}

/// 补齐 coding 能力：shell + rg + run_code。TUI 已注册 read/write/edit/glob，
/// provideCoding 会重复注册 fs 工具（同名抛 StateError），故只补缺失件。
void provideCodingForPlayground(Context app, {required String cwd}) {
  final ShellExecutor shell = provideShellLocal(app);
  final RipgrepBinary? rg = RipgrepBinary.discover();
  if (rg != null) {
    app.effect(() => app.tools.register(RipgrepTool(shell: shell, binary: rg)));
  }
  final SubprocessCodeRuntime codeRuntime = SubprocessCodeRuntime(
    shell: shell,
    executable: 'dart',
    extension: '.dart',
    workingDirectory: cwd,
  );
  app.provide('codeRuntime', codeRuntime);
  app.onDispose(codeRuntime.dispose);
  app.effect(() => app.tools.register(RunCodeTool(
      runtime: codeRuntime,
      tools: app.tools,
      telemetry: app.get<Telemetry>('telemetry'))));
}

const String kPlaygroundPersona = '你是 Playground 编码助手。你可以：\n'
    '- 用 read_file / write_file / edit_file 读写文件，用 glob / rg 搜索代码；\n'
    '- 用 run_code 执行一段 Dart 程序（高危，执行前会请你确认）；\n'
    '- 用户消息里的 <file path="..."> 块是用户引用的文件内容。\n'
    '需要信息时调用工具，否则直接简洁回答。';

const String kPlaygroundUsage = '用法：dart run example/playground.dart '
    '[--session <id>] [--first <文本>] [--cwd <目录>] [--model <名字>]\n'
    '  --session <id>   启动会话 id（默认 $kTuiDefaultSession）\n'
    '  --first <文本>   挂载后自动发一轮\n'
    '  --cwd <目录>     run_code 工作目录（默认当前目录）\n'
    '  --model <名字>   覆盖当前提供商的模型名（默认取 provider 配置）\n'
    '输入 @<路径> 可引用文件（如 @lib/foo.dart 帮我看下这个文件）。\n'
    '会话中用 /provider 管理提供商、/model 切换模型。\n';

/// 取 `--<名字>` 的值；未出现或缺尾值时返回 `null`。
String? parseFlag(List<String> args, String name) {
  for (int index = 0; index + 1 < args.length; index++) {
    if (args[index] == name) return args[index + 1];
  }
  return null;
}

/// 无 Key 时的离线脚本模型：含「执行/运行/代码」且未用过工具时请求一次
/// run_code（真实执行 Dart 程序），其余直接回显。
class _OfflineProvider implements LlmProvider {
  @override
  String get name => 'offline';

  @override
  Future<LlmResult> chat(List<LlmMessage> messages,
      {Map<String, dynamic>? options,
      List<Map<String, dynamic>>? tools}) async {
    final String user = _lastUser(messages);
    final bool toolUsed = messages.any((LlmMessage m) => m.role == 'tool');
    if (!toolUsed && _asksCode(user)) {
      return LlmResult(
        content: '',
        provider: 'offline',
        model: 'scripted',
        toolCalls: <LlmToolCall>[
          LlmToolCall(
              id: 'offline-1',
              name: 'run_code',
              arguments: '{"program":${jsonEncode(_offlineProgram)}}')
        ],
      );
    }
    return LlmResult(
      content: '（离线 Demo）未接入真实模型。你说的是：「$user」。\n'
          '设置 ARK_API_KEY / DEEPSEEK_API_KEY 后重跑即可与真实模型对话。',
      provider: 'offline',
      model: 'scripted',
    );
  }

  @override
  Stream<LlmStreamEvent> chatStream(List<LlmMessage> messages,
          {Map<String, dynamic>? options, List<Map<String, dynamic>>? tools}) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}

  static bool _asksCode(String text) =>
      text.contains('执行') || text.contains('运行') || text.contains('代码');

  static String _lastUser(List<LlmMessage> messages) {
    for (final LlmMessage m in messages.reversed) {
      if (m.role == 'user') return m.content;
    }
    return '';
  }
}

const String _offlineProgram = 'import \'dart:io\';\n'
    'void main() {\n'
    '  print(\'当前时间: \' + DateTime.now().toIso8601String());\n'
    '  print(\'Playground run_code 执行成功。\');\n'
    '}';
