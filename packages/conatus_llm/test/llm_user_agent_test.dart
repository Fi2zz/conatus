/// LLM 请求的 User-Agent：默认值与自定义（伪装）。
library;

import 'dart:convert';

import 'package:conatus_llm/conatus_llm.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// 记录请求头的假客户端。
class _Recorder {
  final List<Map<String, String>> headers = <Map<String, String>>[];

  MockClient get client => MockClient((http.Request request) async {
        headers.add(Map<String, String>.from(request.headers));
        return http.Response(
          jsonEncode(<String, dynamic>{
            'id': '1',
            'object': 'chat.completion',
            'model': 'm',
            'choices': <dynamic>[
              <String, dynamic>{
                'index': 0,
                'message': <String, dynamic>{'role': 'assistant', 'content': 'ok'},
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
        );
      });
}

const List<LlmMessage> messages = <LlmMessage>[LlmMessage('user', 'hi')];

void main() {
  test('默认 User-Agent：ConatusCode/0.16', () async {
    final _Recorder recorder = _Recorder();
    final DoubaoProvider provider = DoubaoProvider(
      apiKey: 'k',
      client: recorder.client,
    );

    await provider.chat(messages);

    expect(recorder.headers.last['User-Agent'], kDefaultLlmUserAgent);
    provider.close();
  });

  test('自定义 User-Agent（伪装 dsh）', () async {
    final _Recorder recorder = _Recorder();
    final OpenAiCompatibleProvider provider = OpenAiCompatibleProvider(
      name: 'dsh',
      baseUrl: 'https://api.deepseek.example/v1',
      model: 'deepseek-v4-1-flash',
      userAgent: 'dsh/0.1.2',
      apiKey: 'k',
      client: recorder.client,
    );

    await provider.chat(messages);

    expect(recorder.headers.last['User-Agent'], 'dsh/0.1.2');
    provider.close();
  });

  test('流式请求同样携带 User-Agent', () async {
    final _Recorder recorder = _Recorder();
    final DeepSeekProvider provider = DeepSeekProvider(
      apiKey: 'k',
      client: recorder.client,
    );

    await provider.chatStream(messages).drain<void>();

    expect(recorder.headers.last['User-Agent'], kDefaultLlmUserAgent);
    provider.close();
  });
}
