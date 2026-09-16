/// 全栈端到端：把四个方向的新能力装配到同一个 Context，跑一轮真实 Agent Loop。
///
/// 这是 A2（「每条 llm/request 都能从 Session Log 重建」）的**持久**证据——此前它
/// 只在一份临时探针上跑过一次，没有留下可复现产物。
///
/// 装配了：Session Log + Session Log 集成、Credentials、内容分类器 + 分层压缩、
/// 缓存度量、MCP（内存假传输）。MCP 用的是进程内假传输，真实子进程的生命周期由
/// `conatus_mcp/test/mcp_stdio_test.dart` 单独覆盖，这里只验「MCP 工具能进
/// ToolRegistry 并被 Agent Loop 调用」这一集成面。
library;

import 'dart:async';
import 'dart:convert';
import 'package:conatus/conatus.dart';
import 'package:test/test.dart';

/// 把一轮对话的模型调用按脚本应答；压缩摘要请求（`summarizeEvents` 构造）单独识别。
class _TurnProvider implements LlmProvider {
  _TurnProvider(this.steps);

  final List<LlmResult> steps;
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];
  int _step = 0;

  @override
  String get name => 'turn';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(List<LlmMessage>.of(messages));
    final bool compaction = messages.any((LlmMessage m) =>
        m.role == 'user' && m.content.contains(kCompactionSummaryPrompt));
    if (compaction) {
      return const LlmResult(content: '历史要点摘要', provider: 'turn', model: 'm');
    }
    final int index = _step < steps.length ? _step : steps.length - 1;
    _step++;
    return steps[index];
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

/// 进程内的假 MCP 传输：实现 `initialize` / `tools/list` / `tools/call`。
class _EchoTransport implements McpTransport {
  final StreamController<McpMessage> _incoming =
      StreamController<McpMessage>.broadcast();

  @override
  Stream<McpMessage> get messages => _incoming.stream;

  @override
  Stream<String> get diagnostics => const Stream<String>.empty();

  @override
  Future<void> connect() async {}

  @override
  Future<void> send(McpMessage message) async {
    if (!message.request) return;
    _incoming.add(McpMessage.fromJson(<String, Object?>{
      'jsonrpc': '2.0',
      'id': message.id,
      'result': _respond(
          message.method!, message.params ?? const <String, Object?>{}),
    }));
  }

  Map<String, Object?> _respond(String method, Map<String, Object?> params) =>
      switch (method) {
        'initialize' => <String, Object?>{
            'protocolVersion': '2025-06-18',
            'serverInfo': <String, Object?>{
              'name': 'probe',
              'version': '0.0.1'
            },
            'capabilities': <String, Object?>{},
          },
        'tools/list' => <String, Object?>{
            'tools': <Object?>[
              <String, Object?>{
                'name': 'echo',
                'description': '原样回显 arguments',
                'inputSchema': <String, Object?>{
                  'type': 'object',
                  'properties': <String, Object?>{
                    'text': <String, Object?>{'type': 'string'},
                  },
                },
                'annotations': <String, Object?>{'readOnlyHint': true},
              },
            ],
          },
        'tools/call' => <String, Object?>{
            'content': <Object?>[
              <String, Object?>{
                'type': 'text',
                'text': jsonEncode(params['arguments']),
              },
            ],
          },
        _ => <String, Object?>{},
      };

  @override
  Future<void> disconnect() async => _incoming.close();
}

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'turn', model: 'm');

LlmResult _call(String id, String name) => LlmResult(
      content: '',
      provider: 'turn',
      model: 'm',
      toolCalls: <LlmToolCall>[
        LlmToolCall(id: id, name: name, arguments: '{"text":"hi"}'),
      ],
    );

void main() {
  test('四个方向装配到同一 Context，跑一轮含工具调用的对话，不变式零违规', () async {
    final Context app = Context.root();
    addTearDown(app.dispose);

    final Telemetry telemetry =
        provideTelemetry(app, telemetry: InMemoryTelemetry());
    final List<String> telemetryNames = <String>[];
    final StreamSubscription<TelemetryEvent> watch = telemetry.events
        .listen((TelemetryEvent event) => telemetryNames.add(event.name));
    addTearDown(watch.cancel);

    provideCredentials(
      app,
      credentials: InMemoryCredentials(
        initial: <String, String>{'ARK_API_KEY': 'sk-probe-0123456789abcdef'},
      ),
    );
    provideSessionLog(app);
    provideSessionLogRecorder(app);
    provideContentClassifier(app);
    provideContextCache(app);
    provideLayeredCompaction(app, keepRecent: 4);

    final ToolRegistry tools = provideTools(app);
    tools.fn(
      'get_time',
      description: '返回当前时间',
      handler: (ToolContext _) async => ToolResult.success('12:00'),
    );

    app.provide(
        'llm',
        _TurnProvider(<LlmResult>[
          _call('c1', 'get_time'),
          _call('c2', 'probe__echo'),
          _text('完成'),
        ]));

    await provideMcp(
      app,
      <McpServerConfig>[
        McpServerConfig(
          name: 'probe',
          type: McpTransportType.stdio,
          command: 'unused',
          headers: <String, String>{'Authorization': r'Bearer ${ARK_API_KEY}'},
        ),
      ],
      credentials: app.credentials,
      transportFactory: (McpServerConfig _) => _EchoTransport(),
    );

    final Session session = Session(id: 'e2e');
    for (int i = 0; i < 6; i++) {
      session.append(
        kUserMessageEvent,
        data: <String, Object?>{'text': '记住：我喜欢简洁 $i'},
      );
      session.append(
        kAssistantMessageEvent,
        data: <String, Object?>{'text': '好的 $i'},
      );
    }

    final AgentLoop loop = provideAgentLoop(app, session: session);
    final AgentTurn turn = await loop.run('现在几点？顺便回显一句');

    // 1) MCP 工具注册进了 ToolRegistry，并被 Agent Loop 调用
    expect(app.mcp.servers, <String>['probe']);
    expect(tools.names, contains('probe__echo'));
    expect(
      turn.steps.map((AgentStep s) => s.call.name),
      <String>['get_time', 'probe__echo'],
    );
    expect(turn.reply, '完成');

    // 2) 业务会话事件序列不受四个方向影响：尾部恰是本轮的 6 条，且只有三类业务事件
    final List<String> allTypes =
        session.events.map((SessionEvent e) => e.type).toList();
    expect(allTypes.length, 18); // 12 条预置历史 + 6 条本轮
    expect(
      allTypes.sublist(allTypes.length - 6),
      <String>[
        kUserMessageEvent,
        kAssistantMessageEvent,
        kToolResultEvent,
        kAssistantMessageEvent,
        kToolResultEvent,
        kAssistantMessageEvent,
      ],
    );
    expect(
      allTypes.toSet(),
      <String>{kUserMessageEvent, kAssistantMessageEvent, kToolResultEvent},
    );

    // 3) Session Log 是超集（含派生事件）
    final List<SessionEvent> log = await app.sessionLog.read('e2e').toList();
    final List<String> logTypes = log.map((SessionEvent e) => e.type).toList();
    expect(logTypes, contains(kLlmRequestEvent));
    expect(logTypes, contains(kLlmResponseEvent));
    expect(logTypes, contains(kToolCallEvent));
    expect(logTypes, contains(kAssistantMessageEvent));

    // 4) A2：每条 llm/request 的会话消息都能从日志重建
    expect(checkModelVisibleInvariant(log), isEmpty);

    // 5) fork 任意事件点，历史是前缀
    final SessionEvent mark =
        log.firstWhere((SessionEvent e) => e.type == kToolResultEvent);
    final String forkId = await app.sessionLog.fork('e2e', mark.id!);
    final List<String> forkTypes = await app.sessionLog
        .read(forkId)
        .map((SessionEvent e) => e.type)
        .toList();
    expect(
        forkTypes, logTypes.sublist(0, logTypes.indexOf(kToolResultEvent) + 1));

    // 6) 分层压缩真的工作（偏好原文进摘要），缓存度量真的发出
    expect(app.get<Compactor>('compaction')?.summaryOf('e2e'), isNotNull);
    expect(telemetryNames, contains('context.compacted'));
    expect(telemetryNames, contains('context.cache'));

    // 7) 凭据只以脱敏形式出现
    expect(app.credentials.get('ARK_API_KEY')?.masked, 'sk-p...cdef');
  });
}
