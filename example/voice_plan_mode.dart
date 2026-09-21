// 演示：Plan Mode 语音闭环 —— Agent 先用 plan_write 迭代草稿，再经
// exit_plan_mode 提交定稿；VoiceApproval 用 TTS 播报计划摘要 + ASR 听取
// 口头确认。批准后 Plan Mode 退出、Agent 开始执行；拒绝则带反馈修订计划。
//
// 运行前设置环境变量：
//   export ARK_API_KEY="你的火山方舟 API Key"   # LLM（或 DEEPSEEK_API_KEY）
//   export VOLC_TTS_API_KEY="你的火山 TTS Key"  # TTS（或 APP_KEY + ACCESS_TOKEN）
//   export VOLC_ASR_API_KEY="你的火山 ASR Key"  # ASR（或 APP_KEY + ACCESS_KEY）
// 另需系统安装 ffmpeg（麦克风采集）；播放用 macOS 自带的 afplay，其他平台
// 音频会落盘到临时目录并打印路径。
//
// 运行：
//   dart run example/voice_plan_mode.dart
//
// 输入 "exit" 结束。每条任务都先进入 plan mode：模型只能调用 web_search /
// ask_user 等只读工具（web_search 走 DuckDuckGo，免 API Key），提交计划后
// 音箱会播报「我打算分 N 步完成：…。可以吗？」——说「可以」即执行，
// 说「不用查天气了」之类则修订计划。Plan Mode 下调用有副作用的工具会被
// PLAN_MODE_BLOCKED 拦截（见 providePlanMode 的中间件）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conatus/conatus.dart';

Future<void> main() async {
  final Context app = Context.root(name: 'voice-app');

  // ── 基础设施：工具 / LLM / 会话 / 提示词 / 可观测性 ───────────
  provideTools(app);
  provideTelemetry(app, telemetry: ConsoleTelemetry());
  instrumentTools(app);
  provideLlm(app, llm: defaultFallbackLlm(credentials: EnvCredentials()));

  final SystemPrompt prompt = provideSystemPrompt(app);
  prompt.section(PromptSection(
    name: 'persona',
    text: () => '你是智能音箱里的助手。回答简短口语化，需要实时信息时调用工具。',
  ));
  provideTimePrompt(app);

  final SessionStore sessions = provideSessions(app);
  final Session session = sessions.create(id: 'voice');

  // ask_user 文本提问（与语音审批是两条独立交互路径）。
  final CliAskUser ask = CliAskUser();
  provideAskUser(app, askUser: ask);
  final StreamSubscription<String> inputSub = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(ask.submit);
  app.onDispose(inputSub.cancel);

  // plan_write 草稿工具：与 exit_plan_mode（提交定稿）共存。
  providePlanTool(app, session: session);

  // 联网搜索：plan:policy 段引导模型先查资料再规划。
  provideSearch(app);
  provideWebTools(app);

  // ── 语音审批 + Plan Mode ─────────────────────────────────────
  final VoiceApproval voice = VoiceApproval(
    tts: app.tts,
    asr: app.asr,
    capture: FfmpegMicSource.new,
  );
  provideApproval(app, approval: voice);

  final PlanMode planMode = providePlanMode(app, session: session);
  final AgentLoop agent = provideAgentLoop(app, session: session);

  print('语音 Plan Mode 已启动（每条任务先规划、语音确认后执行）。'
      '输入 "exit" 结束。');
  while (true) {
    final String line = await ask.ask('你 >');
    if (line.trim().toLowerCase() == 'exit') break;
    if (line.trim().isEmpty) continue;

    // 上一条任务获批后 Plan Mode 已退出，这里为下一条任务重新进入。
    if (planMode.state == PlanModeState.inactive) planMode.enter();
    try {
      final AgentTurn turn = await agent.run(line);
      print('AI > ${turn.reply}');
    } on LlmException catch (e) {
      print('错误 > ${e.message}');
    }
  }

  app.dispose();
}

/// 语音友好的审批：Agent 口述计划摘要，用户口头确认。
///
/// [Approval] 的语音实现：只依赖 `tts` / `asr` 两个能力缝，Plan Mode 本身
/// 并不感知审批是语音还是文本。超时或无法判断均视为拒绝（保守策略，
/// 与 [AskUserApproval] 一致）。
class VoiceApproval implements Approval {
  /// [capture] 每次聆听新建一个音频源（麦克风源是单次使用的）。
  VoiceApproval({
    required this.tts,
    required this.asr,
    required this.capture,
    this.affirmativeWords = const <String>{
      '可以',
      '好',
      '行',
      '嗯',
      '对',
      '是',
      'ok',
      'yes'
    },
    this.negativeWords = const <String>{'不', '不用', '不行', '换个', '算了', 'no'},
    this.listenWindow = const Duration(seconds: 5),
    this.timeout = const Duration(seconds: 15),
  });

  /// 语音合成服务。
  final TtsService tts;

  /// 语音识别服务。
  final AsrService asr;

  /// 音频来源工厂（桌面为 ffmpeg 麦克风；智能音箱接设备麦克风）。
  final AsrAudioSource Function() capture;

  /// 视为肯定的回答（小写比较）。
  final Set<String> affirmativeWords;

  /// 视为否定的回答；判定优先于 [affirmativeWords]。
  final Set<String> negativeWords;

  /// 单次聆听的采集窗口：说完请保持安静，窗口结束自动停止采集。
  final Duration listenWindow;

  /// 整个确认流程的超时，超时视为拒绝。
  final Duration timeout;

  final StreamController<ApprovalRequest> _pending =
      StreamController<ApprovalRequest>.broadcast();

  @override
  Stream<ApprovalRequest> get pending => _pending.stream;

  /// 语音审批不做预授权：没有「静默放行」这条路径，每次都要口头确认。
  @override
  Future<bool> preapproved(ApprovalRequest request) async => false;

  @override
  Future<bool> requestPlan(Plan plan) => _confirm(summarizePlan(plan));

  @override
  Future<bool> request(ApprovalRequest request) async {
    if (!_pending.isClosed) _pending.add(request);
    final String detail =
        request.description.isEmpty ? '' : '（${request.description}）';
    return _confirm('是否允许执行 "${request.toolName}"？$detail');
  }

  @override
  Future<void> close() async {
    if (!_pending.isClosed) await _pending.close();
  }

  /// 播报提问并听取一次回答；超时视为拒绝。
  Future<bool> _confirm(String prompt) async {
    stdout.writeln('播报 > $prompt');
    final List<int> audio = await tts.synthesize(prompt);
    await _playAudio(audio);
    try {
      final String answer = await _listen().timeout(timeout);
      stdout.writeln('识别 > $answer');
      return classifyVoiceAnswer(answer,
          affirmativeWords: affirmativeWords, negativeWords: negativeWords);
    } on TimeoutException {
      stdout.writeln('聆听超时，视为拒绝。');
      return false;
    }
  }

  /// 采集一个 [listenWindow] 的语音并转写为文本。
  Future<String> _listen() async {
    final AsrAudioSource source = capture();
    final List<int> bytes = <int>[];
    final Completer<void> done = Completer<void>();
    await source.start();
    final StreamSubscription<List<int>> sub =
        source.bytes.listen(bytes.addAll, onDone: () {
      if (!done.isCompleted) done.complete();
    });
    Timer(listenWindow, () async {
      await source.stop();
    });
    try {
      await done.future;
    } finally {
      await sub.cancel();
    }
    return asr.transcribeText(
      Stream<List<int>>.fromIterable(<List<int>>[bytes]),
      audioFormat: source.format,
      language: 'zh-CN',
    );
  }
}

/// 把结构化的 [Plan] 转成口语化摘要：只播步骤数 + 前 3 步，
/// 剩余步骤用一句「后面还有 N 步」带过；想听细节可以再问。
String summarizePlan(Plan plan) {
  final int total = plan.steps.length;
  final String firstFew =
      plan.steps.take(3).map((PlanStep s) => s.text).join('，然后');
  if (total <= 3) return '我打算分 $total 步完成：$firstFew。可以吗？';
  return '我打算分 $total 步完成，前几步是：$firstFew，'
      '后面还有 ${total - 3} 步。可以吗？';
}

/// 否定优先的保守判定：「不用查天气」含否定词，不能误判为肯定；
/// 无法判断时返回 false（视为拒绝，反馈由模型带回修订计划）。
bool classifyVoiceAnswer(
  String text, {
  required Set<String> affirmativeWords,
  required Set<String> negativeWords,
}) {
  final String normalized = text.trim().toLowerCase();
  if (negativeWords.any(normalized.contains)) return false;
  if (affirmativeWords.any(normalized.contains)) return true;
  return false;
}

/// 播放合成音频：macOS 用 afplay；其他平台落盘并打印路径。
Future<void> _playAudio(List<int> bytes) async {
  final File file =
      await File('${Directory.systemTemp.path}/conatus_plan_mode.mp3')
          .writeAsBytes(bytes, flush: true);
  if (!Platform.isMacOS) {
    stdout.writeln('已写出音频：${file.path}（当前平台请自行播放）');
    return;
  }
  final ProcessResult result = await Process.run('afplay', <String>[file.path]);
  if (result.exitCode != 0) {
    stdout.writeln('afplay 播放失败：${result.stderr}');
  }
}
