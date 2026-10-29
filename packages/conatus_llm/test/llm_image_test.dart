import 'dart:convert';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'builtin_provider_helpers.dart';

const LlmImage _image = LlmImage(
  mimeType: 'image/png',
  base64Data: 'aGVsbG8=',
);

MockClient _captureClient(List<Map<String, dynamic>> bodies) {
  return MockClient((http.Request request) async {
    bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
    return http.Response(
      jsonEncode(<String, dynamic>{
        'id': 'chatcmpl-test',
        'object': 'chat.completion',
        'model': 'test-model',
        'choices': <dynamic>[
          <String, dynamic>{
            'index': 0,
            'message': <String, dynamic>{'role': 'assistant', 'content': 'ok'},
            'finish_reason': 'stop',
          },
        ],
        'usage': <String, dynamic>{},
      }),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  });
}

void main() {
  group('LlmMessage.toJson', () {
    test('无图片时 content 为字符串', () {
      const LlmMessage message = LlmMessage('user', '你好');
      expect(message.toJson()['content'], '你好');
    });

    test('有图片时 content 为 parts 数组', () {
      const LlmMessage message = LlmMessage('user', '看这张图', images: [_image]);
      final Map<String, dynamic> json = message.toJson();
      final List<dynamic> parts = json['content'] as List<dynamic>;
      expect(parts, hasLength(2));
      expect(parts[0], <String, String>{'type': 'text', 'text': '看这张图'});
      expect(parts[1]['type'], 'image_url');
      expect(
        parts[1]['image_url']['url'],
        'data:image/png;base64,aGVsbG8=',
      );
    });
  });

  group('多模态请求体', () {
    test('chat 形态：content 为 parts 数组', () async {
      final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];
      final provider = doubaoProviderForTest(
        apiKey: 'test-key',
        client: _captureClient(bodies),
      );
      await provider.chat(
        <LlmMessage>[
          const LlmMessage('user', '看这张图', images: [_image])
        ],
      );

      final List<dynamic> messages = bodies.single['messages'] as List<dynamic>;
      final List<dynamic> content =
          (messages.single as Map<String, dynamic>)['content'] as List<dynamic>;
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'image_url');
      expect(content[1]['image_url']['url'], _image.dataUrl);
    });

    test('responses 形态：content 追加 input_image', () async {
      final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];
      final provider = doubaoProviderForTest(
        apiKey: 'test-key',
        apiStyle: LlmApiStyle.responses,
        client: _captureClient(bodies),
      );
      await provider.chat(
        <LlmMessage>[
          const LlmMessage('user', '看这张图', images: [_image])
        ],
      );

      final List<dynamic> input = bodies.single['input'] as List<dynamic>;
      final List<dynamic> content =
          (input.single as Map<String, dynamic>)['content'] as List<dynamic>;
      expect(content[0]['type'], 'input_text');
      expect(content[1]['type'], 'input_image');
      expect(content[1]['image_url'], _image.dataUrl);
    });
  });

  group('工具结果图片', () {
    const List<LlmMessage> toolMessages = <LlmMessage>[
      LlmMessage('user', '读图'),
      LlmMessage(
        'assistant',
        '',
        toolCalls: <LlmToolCall>[
          LlmToolCall(id: 'call_1', name: 'read'),
        ],
      ),
      LlmMessage(
        'tool',
        '图像已读取',
        toolCallId: 'call_1',
        images: <LlmImage>[_image],
      ),
    ];

    test('chat 形态：tool 文本后追加 user 图片消息', () async {
      final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];
      final provider = doubaoProviderForTest(
        apiKey: 'test-key',
        client: _captureClient(bodies),
      );
      await provider.chat(toolMessages);

      final List<dynamic> messages = bodies.single['messages'] as List<dynamic>;
      final Map<String, dynamic> tool = messages[2] as Map<String, dynamic>;
      expect(tool['role'], 'tool');
      expect(tool['content'], '图像已读取');
      expect(tool['tool_call_id'], 'call_1');
      final Map<String, dynamic> user = messages[3] as Map<String, dynamic>;
      expect(user['role'], 'user');
      final List<dynamic> parts = user['content'] as List<dynamic>;
      expect(parts.last['type'], 'image_url');
      expect(parts.last['image_url']['url'], _image.dataUrl);
    });

    test('responses 形态：function_call_output 后追加 user 图片消息', () async {
      final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];
      final provider = doubaoProviderForTest(
        apiKey: 'test-key',
        apiStyle: LlmApiStyle.responses,
        client: _captureClient(bodies),
      );
      await provider.chat(toolMessages);

      final List<dynamic> input = bodies.single['input'] as List<dynamic>;
      final List<String> types = <String>[
        for (final dynamic item in input) (item as Map<String, dynamic>)['type'] as String,
      ];
      expect(types, containsAllInOrder(<String>[
        'function_call_output',
        'message',
      ]));
      final Map<String, dynamic> user =
          input.last as Map<String, dynamic>;
      final List<dynamic> content = user['content'] as List<dynamic>;
      expect(content.last['type'], 'input_image');
    });

    test('responses 形态：PDF 用 input_file', () async {
      final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];
      final provider = doubaoProviderForTest(
        apiKey: 'test-key',
        apiStyle: LlmApiStyle.responses,
        client: _captureClient(bodies),
      );
      await provider.chat(<LlmMessage>[
        const LlmMessage('user', '读 PDF'),
        const LlmMessage(
          'tool',
          'PDF 已读取',
          toolCallId: 'call_1',
          files: <LlmFile>[
            LlmFile(
              mimeType: 'application/pdf',
              base64Data: 'JVBERg==',
              filename: 'a.pdf',
            ),
          ],
        ),
      ]);

      final List<dynamic> input = bodies.single['input'] as List<dynamic>;
      final Map<String, dynamic> user = input.last as Map<String, dynamic>;
      final List<dynamic> content = user['content'] as List<dynamic>;
      final Map<String, dynamic> file = content.last as Map<String, dynamic>;
      expect(file['type'], 'input_file');
      expect(file['filename'], 'a.pdf');
      expect(file['file_data'], 'JVBERg==');
    });

    test('chat 形态：PDF 降级为文本提示', () async {
      final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];
      final provider = doubaoProviderForTest(
        apiKey: 'test-key',
        client: _captureClient(bodies),
      );
      await provider.chat(<LlmMessage>[
        const LlmMessage('user', '读 PDF'),
        const LlmMessage(
          'tool',
          'PDF 已读取',
          toolCallId: 'call_1',
          files: <LlmFile>[
            LlmFile(
              mimeType: 'application/pdf',
              base64Data: 'JVBERg==',
              filename: 'a.pdf',
            ),
          ],
        ),
      ]);

      final List<dynamic> messages = bodies.single['messages'] as List<dynamic>;
      final Map<String, dynamic> last =
          messages.last as Map<String, dynamic>;
      expect(last['role'], 'user');
      expect(last['content'], contains('不支持内联文件'));
    });
  });
}
