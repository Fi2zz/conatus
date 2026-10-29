import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.script);

  final List<LlmResult> script;
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(List<LlmMessage>.of(messages));
    return script[calls.length - 1 < script.length ? calls.length - 1 : 0];
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

const LlmImage _image = LlmImage(
  mimeType: 'image/png',
  base64Data: 'aGVsbG8=',
);

class _ImageTool extends Tool {
  @override
  String get name => 'read';

  @override
  String get description => '读取图片';

  @override
  Future<ToolResult> call(ToolContext ctx) async => ToolResult.success(
        '图像已读取',
        images: const <ToolImage>[
          ToolImage(mimeType: 'image/png', base64Data: 'aGVsbG8='),
        ],
      );
}

class _FileTool extends Tool {
  @override
  String get name => 'read';

  @override
  String get description => '读取 PDF';

  @override
  Future<ToolResult> call(ToolContext ctx) async => ToolResult.success(
        'PDF 已读取',
        files: const <ToolFile>[
          ToolFile(
            mimeType: 'application/pdf',
            base64Data: 'JVBERg==',
            filename: 'a.pdf',
          ),
        ],
      );
}

LlmResult _call(String id, String name) => LlmResult(
      content: '',
      provider: 'scripted',
      model: 'm',
      toolCalls: <LlmToolCall>[LlmToolCall(id: id, name: name)],
    );

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

void main() {
  group('imagesToJson / imagesFromJson', () {
    test('序列化后可完整还原', () {
      final List<LlmImage> restored = imagesFromJson(imagesToJson([_image]));
      expect(restored, hasLength(1));
      expect(restored.single.mimeType, 'image/png');
      expect(restored.single.base64Data, 'aGVsbG8=');
    });

    test('非法负载返回空列表', () {
      expect(imagesFromJson(null), isEmpty);
      expect(imagesFromJson(['not-a-map']), isEmpty);
      expect(
          imagesFromJson([
            {'mimeType': 'image/png'}
          ]),
          isEmpty);
    });
  });

  group('deriveAgentMessages — 图片回放', () {
    test('用户事件含 images 时还原为带图片的消息', () {
      final SessionEvent event = SessionEvent.create(
        sessionId: 's1',
        seq: 0,
        type: kUserMessageEvent,
        data: <String, Object?>{
          'text': '看这张图',
          'images': imagesToJson([_image]),
        },
      );

      final LlmMessage message = deriveAgentMessages([event]).single;
      expect(message.role, 'user');
      expect(message.content, '看这张图');
      expect(message.images.single.mimeType, 'image/png');
      expect(message.images.single.dataUrl, _image.dataUrl);
    });
  });

  group('AgentLoop.run — 图片入参', () {
    test('图片随用户消息发给模型并写入会话事件', () async {
      final _ScriptedProvider provider = _ScriptedProvider(const <LlmResult>[
        LlmResult(content: '看到图了', provider: 'scripted', model: 'm'),
      ]);
      final Session session = Session(id: 's1');
      final AgentLoop loop = AgentLoop(
        llm: provider,
        tools: ToolRegistry(),
        session: session,
      );

      await loop.run('看这张图', images: [_image]);

      final LlmMessage userMessage =
          provider.calls.single.where((m) => m.role == 'user').single;
      expect(userMessage.images.single.mimeType, 'image/png');

      final SessionEvent event =
          session.events.where((e) => e.type == kUserMessageEvent).single;
      final Object? data = event.data;
      final Map<Object?, Object?> payload = data as Map<Object?, Object?>;
      expect(imagesFromJson(payload['images']), hasLength(1));
    });

    test('工具结果图片进入下一轮 tool 消息', () async {
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _call('call_1', 'read'),
        _text('收到图片'),
      ]);
      final ToolRegistry tools = ToolRegistry()..register(_ImageTool());
      final AgentLoop loop = AgentLoop(llm: provider, tools: tools);

      await loop.run('读图');

      final LlmMessage toolMessage =
          provider.calls[1].singleWhere((m) => m.role == 'tool');
      expect(toolMessage.content, '图像已读取');
      expect(toolMessage.images.single.mimeType, 'image/png');
      expect(toolMessage.images.single.base64Data, 'aGVsbG8=');
    });
    test('工具结果 PDF 进入下一轮 tool 消息', () async {
      final _ScriptedProvider provider = _ScriptedProvider(<LlmResult>[
        _call('call_2', 'read'),
        _text('收到 PDF'),
      ]);
      final ToolRegistry tools = ToolRegistry()..register(_FileTool());
      final AgentLoop loop = AgentLoop(llm: provider, tools: tools);

      await loop.run('读 PDF');

      final LlmMessage toolMessage =
          provider.calls[1].singleWhere((m) => m.role == 'tool');
      expect(toolMessage.files.single.mimeType, 'application/pdf');
      expect(toolMessage.files.single.filename, 'a.pdf');
      expect(toolMessage.files.single.base64Data, 'JVBERg==');
    });
  });
}
