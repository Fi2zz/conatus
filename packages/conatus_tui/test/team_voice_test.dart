/// VoiceReporter 与 summarizeTeamProgress 测试。
///
/// TTS 用 Fake provider 注入真实 [TtsService]（不 Mock 框架）；音频目标用
/// 内存 [BytesAudioSink] 与回调 sink 验证。
library;

import 'dart:async';

import 'package:conatus_team/conatus_team.dart';
import 'package:conatus_tts/conatus_tts.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

/// 记录播报文本的假 TTS provider。
class FakeTtsProvider implements TtsProvider {
  final List<String> spoken = <String>[];

  @override
  String get name => 'fake';

  @override
  TtsAudioFormat get audioFormat => const TtsAudioFormat();

  @override
  TtsVoice? get defaultVoice => null;

  @override
  Future<TtsSession> start(
    TtsAudioSink sink, {
    TtsVoice? voice,
    TtsAudioFormat? format,
    double? speed,
    double? volume,
    double? pitch,
  }) async {
    return _FakeSession(spoken.add);
  }
}

class _FakeSession implements TtsSession {
  _FakeSession(this._onText);
  final void Function(String) _onText;

  @override
  void send(String text) => _onText(text);

  @override
  Future<void> finish() async {}

  @override
  void close() {}
}

/// 手写团队替身（同 team_subscription_test，独立文件各自持有）。
class FakeAgentTeam implements AgentTeam {
  final StreamController<AgentTeamEvent> _events =
      StreamController<AgentTeamEvent>.broadcast();

  @override
  String get leadId => 'lead';
  @override
  List<Teammate> get members => const <Teammate>[];
  @override
  List<TeamTask> get tasks => const <TeamTask>[];
  @override
  Stream<AgentTeamEvent> get changes => _events.stream;

  void emit(AgentTeamEvent event) => _events.add(event);

  @override
  Future<Teammate> spawn({
    required String name,
    List<String>? tools,
    String? systemPrompt,
  }) =>
      throw UnimplementedError();
  @override
  Future<void> send(String teammateId, String message) =>
      throw UnimplementedError();
  @override
  Future<String> ask(String teammateId, String message) =>
      throw UnimplementedError();
  @override
  Future<Teammate> wait(String teammateId, {Duration? timeout}) =>
      throw UnimplementedError();
  @override
  Future<List<Teammate>> waitAll({Duration? timeout}) =>
      throw UnimplementedError();
  @override
  Future<void> interrupt(String teammateId) => throw UnimplementedError();
  @override
  Future<void> remove(String teammateId) => throw UnimplementedError();
  @override
  Future<TeamTask> createTask({
    required String description,
    List<String> dependsOn = const <String>[],
    String? assigneeId,
  }) =>
      throw UnimplementedError();
  @override
  Future<TeamTask> claimTask(
    String taskId,
    String teammateId, {
    int? version,
  }) =>
      throw UnimplementedError();
  @override
  Future<TeamTask> completeTask(
    String taskId,
    String teammateId, {
    Object? result,
    int? version,
  }) =>
      throw UnimplementedError();
  @override
  Future<TeamTask> releaseTask(
    String taskId,
    String teammateId, {
    int? version,
  }) =>
      throw UnimplementedError();
  @override
  TeamTask? task(String id) => throw UnimplementedError();
  @override
  List<TeamTask> claimableBy(String teammateId) => throw UnimplementedError();
  @override
  void dispose() {
    _events.close();
  }
}

Teammate _mate(String id, TeammateStatus status) => Teammate(
      id: id,
      name: id,
      role: TeamRole.member,
      status: status,
      tools: const <String>[],
      createdAt: DateTime.utc(2026, 9, 17),
    );

TeamTask _task(String id, TeamTaskStatus status) => TeamTask(
      id: id,
      description: '审查$id',
      status: status,
      dependsOn: const <String>[],
      version: 1,
      createdAt: DateTime.utc(2026, 9, 17),
    );

Future<void> _flush() async {
  // 让 unawaited 的 _report 完成（speak 链路是同步 fake）。
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('成员完成 / 失败时播报', () async {
    final FakeAgentTeam team = FakeAgentTeam();
    final FakeTtsProvider provider = FakeTtsProvider();
    final VoiceReporter reporter = VoiceReporter(
      team: team,
      tts: TtsService()..register(provider),
      minInterval: Duration.zero,
    );
    team.emit(TeammateStatusChanged(_mate('a', TeammateStatus.done)));
    team.emit(TeammateStatusChanged(_mate('b', TeammateStatus.failed)));
    await _flush();
    expect(provider.spoken, <String>['a 完成了', 'b 失败了']);
    reporter.dispose();
  });

  test('任务完成时播报', () async {
    final FakeAgentTeam team = FakeAgentTeam();
    final FakeTtsProvider provider = FakeTtsProvider();
    final VoiceReporter reporter = VoiceReporter(
      team: team,
      tts: TtsService()..register(provider),
    );
    team.emit(TeamTaskChanged(_task('t1', TeamTaskStatus.done)));
    await _flush();
    expect(provider.spoken, <String>['任务「审查t1」完成了']);
    reporter.dispose();
  });

  test('minInterval 节流：间隔内的重复事件只播一条', () async {
    final FakeAgentTeam team = FakeAgentTeam();
    final FakeTtsProvider provider = FakeTtsProvider();
    final VoiceReporter reporter = VoiceReporter(
      team: team,
      tts: TtsService()..register(provider),
    );
    team.emit(TeammateStatusChanged(_mate('a', TeammateStatus.done)));
    team.emit(TeammateStatusChanged(_mate('b', TeammateStatus.done)));
    await _flush();
    expect(provider.spoken, hasLength(1));
    reporter.dispose();
  });

  test('TeamMessageSent 不播报；enabled=false 不订阅', () async {
    final FakeAgentTeam team = FakeAgentTeam();
    final FakeTtsProvider provider = FakeTtsProvider();
    final VoiceReporter reporter = VoiceReporter(
      team: team,
      tts: TtsService()..register(provider),
    );
    team.emit(const TeamMessageSent('a', 'b', '内部'));
    await _flush();
    expect(provider.spoken, isEmpty);
    reporter.dispose();

    final VoiceReporter disabled = VoiceReporter(
      team: team,
      tts: TtsService()..register(provider),
      enabled: false,
    );
    team.emit(TeammateStatusChanged(_mate('a', TeammateStatus.done)));
    await _flush();
    expect(provider.spoken, isEmpty);
    disabled.dispose();
  });

  test('dispose 后不再播报', () async {
    final FakeAgentTeam team = FakeAgentTeam();
    final FakeTtsProvider provider = FakeTtsProvider();
    final VoiceReporter reporter = VoiceReporter(
      team: team,
      tts: TtsService()..register(provider),
    );
    reporter.dispose();
    team.emit(TeammateStatusChanged(_mate('a', TeammateStatus.done)));
    await _flush();
    expect(provider.spoken, isEmpty);
  });

  test('summarizeTeamProgress：无团队', () {
    expect(
      summarizeTeamProgress(const TeamSnapshot()),
      '现在没有正在进行的团队任务。',
    );
  });

  test('summarizeTeamProgress：按成员状态分组摘要', () {
    final TeamSnapshot snapshot = TeamSnapshot(
      members: <Teammate>[
        _mate('a', TeammateStatus.done),
        _mate('b', TeammateStatus.working),
        _mate('c', TeammateStatus.waiting),
        _mate('d', TeammateStatus.failed),
      ],
      tasks: <TeamTask>[
        _task('t1', TeamTaskStatus.done),
        _task('t2', TeamTaskStatus.claimed),
      ],
    );
    expect(
      summarizeTeamProgress(snapshot),
      '1/2 个任务完成。a完成了，b还在进行，c在等待，d失败了。',
    );
  });

  test('summarizeTeamProgress：全部空闲只报任务数', () {
    final TeamSnapshot snapshot = TeamSnapshot(
      members: <Teammate>[
        _mate('a', TeammateStatus.idle),
        _mate('b', TeammateStatus.idle),
      ],
      tasks: <TeamTask>[_task('t1', TeamTaskStatus.pending)],
    );
    expect(summarizeTeamProgress(snapshot), '0/1 个任务完成。');
  });
}
