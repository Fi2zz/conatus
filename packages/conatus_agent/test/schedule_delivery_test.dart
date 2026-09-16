import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.script);

  final List<LlmResult> script;
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];
  List<Map<String, dynamic>>? lastTools;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(List<LlmMessage>.of(messages));
    lastTools = tools;
    final int index =
        calls.length - 1 < script.length ? calls.length - 1 : script.length - 1;
    return script[index];
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

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

Map<String, Object?> _dueReminder({
  String id = 'schedule-1',
  String prompt = '跟进迁移',
}) =>
    <String, Object?>{
      'version': 1,
      'operation': 'create',
      'schedule': <String, Object?>{
        'id': id,
        'kind': 'at',
        'prompt': prompt,
        'scheduledAt': formatUtcInstant(
            DateTime.now().toUtc().subtract(const Duration(seconds: 5))),
      },
    };

void main() {
  test('到期的提醒驱动一轮对话，并写入派发记录', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    final Session session = Session(id: 's1');
    addTearDown(session.close);
    final _ScriptedProvider llm =
        _ScriptedProvider(<LlmResult>[_text('收到，我来跟进迁移。')]);
    provideTools(ctx);
    ctx.provide('llm', llm);
    provideAgentLoop(ctx, session: session);
    provideSessionSchedule(ctx, session: session);
    provideScheduleTools(ctx);
    session.append(kScheduleChangeEvent, data: _dueReminder());
    provideScheduleRuntime(ctx, deliver: (String text) async {
      await ctx.agentLoop.run(text);
      return true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 400));

    final Iterable<SessionEvent> userMessages = session.events
        .where((SessionEvent event) => event.type == kUserMessageEvent);
    expect(userMessages, hasLength(1));
    expect((userMessages.single.data! as Map<Object?, Object?>)['text'],
        startsWith('[SCHEDULE REMINDER]'));
    expect(
        session.events.where(
            (SessionEvent event) => event.type == kAssistantMessageEvent),
        hasLength(1));
    expect(llm.calls.single.last.content,
        contains('reminder_prompt_json: "跟进迁移"'));
    expect(llm.lastTools?.map((Map<String, dynamic> tool) => tool['name']),
        contains('schedule_create'));
    expect(foldScheduleEvents(session.ownEvents).active, isEmpty);
    expect(
        session.events
            .where((SessionEvent event) => event.type == kScheduleChangeEvent),
        hasLength(2));
  });

  test('会话正在回答时投递被拒绝，记录保持活动', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    final Session session = Session(id: 's1');
    addTearDown(session.close);
    provideTools(ctx);
    ctx.provide('llm', _ScriptedProvider(<LlmResult>[_text('好的。')]));
    provideAgentLoop(ctx, session: session);
    provideSessionSchedule(ctx, session: session);
    provideScheduleTools(ctx);
    session.append(kScheduleChangeEvent, data: _dueReminder());
    int attempts = 0;
    provideScheduleRuntime(ctx, deliver: (String text) async {
      attempts += 1;
      return false;
    });

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(attempts, greaterThan(0));
    expect(
        session.events
            .where((SessionEvent event) => event.type == kUserMessageEvent),
        isEmpty);
    expect(foldScheduleEvents(session.ownEvents).active, hasLength(1));
  });
}
