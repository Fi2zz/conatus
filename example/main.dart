// 演示：Agent Loop 完整闭环 —— 会话 + prompt 装配 + 压缩 + 长记忆 + 工具。
//
// 运行前设置环境变量（二选一或都设）：
//   export ARK_API_KEY="你的火山方舟 API Key"
//   export DEEPSEEK_API_KEY="你的 DeepSeek API Key"
//
// 运行：
//   dart run example/main.dart
//
// 输入 "exit" 结束。试试「现在几点？」观察模型调用 get_time 并回填；
// 「今天几号？」由 system 里的日期锚点直接回答，不经过工具。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conatus/conatus.dart';

Future<void> main() async {
  final app = Context.root(name: 'app');

  // ── 基础设施：工具 / LLM / 会话 / 提示词 / 记忆 / 压缩 ──────────
  provideTools(app);
  app.effect(() => app.tools.fn(
        'get_time',
        description: '返回当前本地时间（RFC 3339，带时区偏移）',
        handler: (ToolContext ctx) async {
          final DateTime now = DateTime.now();
          return ToolResult.success('${now.toIso8601String()}'
              '${formatClockOffset(now.timeZoneOffset)}');
        },
      ));

  // 可观测性：控制台导出 + 工具埋点（tool.called）。
  provideTelemetry(app, telemetry: ConsoleTelemetry());
  instrumentTools(app);

  // fs 能力缝 + read_file 工具 + 大结果驱逐（超阈值落盘，模型按路径读回）。
  provideFileSystemLocal(app);
  app.effect(() => app.tools.fn(
        'read_file',
        description: '读取文件内容',
        params: <ParamSpec>[
          ParamSpec.string('path', required: true, description: '文件路径'),
        ],
        pathParams: <String>['path'],
        handler: (ToolContext ctx) async {
          final FileSystem fs = app.require<FileSystem>('fs');
          try {
            final FsTarget target = await fs.resolve(ctx.str('path'));
            return ToolResult.success(await fs.readText(target));
          } on FsError catch (e) {
            return ToolResult.failure(e.message,
                error: ToolError(e.code.code, e.message));
          }
        },
      ));
  provideToolResultEviction(app);

  // 显式装配「豆包 → DeepSeek」回退链：框架不提供缺省回退，用哪个提供商由调用方
  // 决定（Key 经凭据服务解析，缺省读环境变量）。
  final Credentials credentials = EnvCredentials();
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[
    OpenAiCompatibleProvider(
      name: 'doubao',
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      model: 'doubao-seed-1-8-251228',
      credentialKey: 'ARK_API_KEY',
      credentials: credentials,
    ),
    OpenAiCompatibleProvider(
      name: 'deepseek',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      credentialKey: 'DEEPSEEK_API_KEY',
      credentials: credentials,
    ),
  ]));

  // 工具失败时自省并重试（默认 onError）。
  provideReflection(app);

  // 子 Agent 委托：spawn_agent 在隔离上下文里用白名单工具跑独立循环。
  provideSpawnAgent(app, defaultTools: <String>['get_time', 'read_file']);

  final SessionStore sessions = provideSessions(app);
  final Session session = sessions.create(id: 'cli');

  final SystemPrompt prompt = provideSystemPrompt(app);
  prompt.section(PromptSection(
    name: 'persona',
    text: () => '你是"助手"，一位耐心的助手。需要实时信息时调用工具；否则直接简洁回答。',
  ));
  provideTimePrompt(app); // 日期锚点：模型不必调工具就知道今天

  provideMemory(app);
  provideCompaction(app);

  // ── ask_user：把 stdin 每一行投递给最早等待中的提问 ────────────
  final CliAskUser ask = CliAskUser();
  provideAskUser(app, askUser: ask);
  final StreamSubscription<String> inputSub = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(ask.submit);
  app.onDispose(inputSub.cancel);

  // ── Agent Loop：读取已就绪的服务自动接入 ─────────────────────
  final AgentLoop agent = provideAgentLoop(app, session: session);

  print('Agent 已启动。输入 "exit" 结束。');
  while (true) {
    final String line = await ask.ask('你 >');
    if (line.trim().toLowerCase() == 'exit') break;
    if (line.trim().isEmpty) continue;

    try {
      final AgentTurn turn = await agent.run(line);
      for (final AgentStep step in turn.steps) {
        final String mark = step.result.isError ? '✗' : '✓';
        print('· 工具 $mark ${step.call.name}');
      }
      print('AI > ${turn.reply}');
    } on LlmException catch (e) {
      print('错误 > ${e.message}');
    }
  }

  app.dispose();
}
