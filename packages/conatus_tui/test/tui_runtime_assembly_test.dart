import 'dart:io';

import 'package:conatus_cron/conatus_cron.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

void main() {
  test('装配后 system 带日期锚点，get_time 返回带偏移的时刻', () async {
    final Directory dir = Directory.systemTemp.createTempSync('conatus-tui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String sep = Platform.pathSeparator;
    final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
      baseDir: dir.path,
      sessionDir: dir.path,
      memoryFile: '${dir.path}${sep}memory.json',
      webTools: false,
      skills: false,
      llm: FallbackLlm(const <LlmProvider>[]),
    );

    final SystemPrompt prompt =
        runtime.app.require<SystemPrompt>('systemPrompt');
    final String anchor = prompt.renderContexts(prompt.assemble());

    expect(anchor, startsWith('[当前时间]'));
    expect(anchor, contains('${DateTime.now().year}-'));

    final ToolResult result =
        await runtime.tools.call(const ToolCall(name: 'get_time'));

    expect(
      result.content,
      matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.*[+-]\d{2}:\d{2}$'),
    );

    await runtime.dispose();
  });

  test('一轮对话里模型看到的 system 带日期锚点', () async {
    final Directory dir = Directory.systemTemp.createTempSync('conatus-tui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String sep = Platform.pathSeparator;
    final _CaptureProvider provider = _CaptureProvider();
    final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
      baseDir: dir.path,
      sessionDir: dir.path,
      memoryFile: '${dir.path}${sep}memory.json',
      webTools: false,
      skills: false,
      llm: FallbackLlm(<LlmProvider>[provider]),
    );
    final ConatusTuiController controller =
        runtime.createController(onExit: () {});

    await controller.start();
    await controller.handleLine('今天几号？');

    expect(provider.calls, isNotEmpty);
    expect(provider.calls.first.first.role, 'system');
    expect(provider.calls.first.first.content, contains('[当前时间]'));

    await runtime.dispose();
  });

  test('cron 任务立即执行：交付进当前会话并回报运行状态', () async {
    final Directory dir = Directory.systemTemp.createTempSync('conatus-tui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String sep = Platform.pathSeparator;
    final _CaptureProvider provider = _CaptureProvider();
    final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
      baseDir: dir.path,
      sessionDir: dir.path,
      memoryFile: '${dir.path}${sep}memory.json',
      webTools: false,
      skills: false,
      llm: FallbackLlm(<LlmProvider>[provider]),
    );
    final ConatusTuiController controller =
        runtime.createController(onExit: () {});

    await controller.start();

    runtime.app.cron.addDynamicTask(<String, Object?>{
      'id': 't1',
      'prompt': '报时',
      'every': 60,
    });
    await runtime.app.cronRuntime.runTaskNow('t1');

    // deliver 投递后 submit 在后台跑；轮询等运行记录推进到终态。
    for (int i = 0; i < 200; i++) {
      final List<CronRunRecord> records = runtime.app.cron.listHistory();
      if (records.isNotEmpty &&
          records.first.status == CronRunStatus.completed) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    final List<CronRunRecord> history = runtime.app.cron.listHistory();
    expect(history, hasLength(1));
    expect(history.single.taskId, 't1');
    expect(history.single.status, CronRunStatus.completed);
    expect(history.single.excerpt, '好的');
    // 任务提示经 framing 注入：找到含 [cron] 标记的那次模型调用。
    expect(
      provider.calls.any((List<LlmMessage> messages) => messages.any(
          (LlmMessage m) =>
              m.content.contains('[cron]') &&
              m.content.contains('<task>') &&
              m.content.contains('报时'))),
      isTrue,
    );

    // 等轮次收尾的会话落盘完成，避免与 dispose 竞态写已删的临时目录。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await runtime.dispose();
  });
}

/// 记录模型实际收到的消息。
class _CaptureProvider implements LlmProvider {
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];

  @override
  String get name => 'capture';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(messages);
    return const LlmResult(content: '好的', provider: 'capture', model: 'm');
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}
