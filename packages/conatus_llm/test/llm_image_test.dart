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
        <LlmMessage>[const LlmMessage('user', '看这张图', images: [_image])],
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
        <LlmMessage>[const LlmMessage('user', '看这张图', images: [_image])],
      );

      final List<dynamic> input = bodies.single['input'] as List<dynamic>;
      final List<dynamic> content =
          (input.single as Map<String, dynamic>)['content'] as List<dynamic>;
      expect(content[0]['type'], 'input_text');
      expect(content[1]['type'], 'input_image');
      expect(content[1]['image_url'], _image.dataUrl);
    });
  });
}
