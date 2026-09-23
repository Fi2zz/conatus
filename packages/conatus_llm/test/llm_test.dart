import 'dart:convert';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'builtin_provider_helpers.dart';

MockClient _okClient(String content, {String model = 'test-model'}) {
  return MockClient((http.Request request) async {
    return http.Response(
      'data: {"choices":[{"delta":{"role":"assistant","content":"$content"},'
      '"finish_reason":"stop"}]}\n\n'
      'data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":20,'
      '"total_tokens":30}}\n\n'
      'data: [DONE]\n\n',
      200,
      headers: <String, String>{
        'content-type': 'text/event-stream; charset=utf-8',
      },
    );
  });
}

MockClient _errClient(int status, String body) {
  return MockClient((_) async => http.Response(body, status));
}

MockClient _sseClient(String sse) {
  return MockClient((http.Request request) async {
    return http.Response(
      sse,
      200,
      headers: <String, String>{
        'content-type': 'text/event-stream; charset=utf-8',
      },
    );
  });
}

void main() {
  group('DoubaoProvider', () {
    test('成功返回结果', () async {
      final provider = doubaoProviderForTest(
        apiKey: 'test-key',
        client: _okClient('你好', model: 'doubao-seed-1-8-251228'),
      );

      final result = await provider.chat(<LlmMessage>[
        const LlmMessage('user', 'hi'),
      ]);

      expect(result.content, '你好');
      expect(result.provider, 'doubao');
      expect(result.model, 'doubao-seed-1-8-251228');
    });

    test('缺少 API Key 抛 LlmException', () async {
      final provider = doubaoProviderForTest(apiKey: '');
      expect(
        () => provider.chat(<LlmMessage>[const LlmMessage('user', 'hi')]),
        throwsA(isA<LlmException>()),
      );
    });

    test('chat 走流式且捕获思考过程 reasoning_content', () async {
      final provider = doubaoProviderForTest(
        apiKey: 'test-key',
        client: _sseClient(
          'data: {"choices":[{"delta":{"reasoning_content":"先想"}}]}\n\n'
          'data: {"choices":[{"delta":{"reasoning_content":"再想"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"回答"},"finish_reason":"stop"}]}\n\n'
          'data: {"choices":[],"usage":{"total_tokens":3}}\n\n'
          'data: [DONE]\n\n',
        ),
      );

      final result = await provider.chat(<LlmMessage>[
        const LlmMessage('user', 'hi'),
      ]);

      expect(result.content, '回答');
      expect(result.reasoning, '先想再想');
      expect(result.provider, 'doubao');
      expect(result.model, 'doubao-seed-1-8-251228');
      expect(result.usage['total_tokens'], 3);
    });

    test('非 200 响应抛 LlmException', () async {
      final provider = doubaoProviderForTest(
        apiKey: 'test-key',
        client: _errClient(401, 'unauthorized'),
      );
      expect(
        () => provider.chat(<LlmMessage>[const LlmMessage('user', 'hi')]),
        throwsA(isA<LlmException>()),
      );
    });
  });

  group('DeepSeekProvider', () {
    test('成功返回结果', () async {
      final provider = deepseekProviderForTest(
        apiKey: 'test-key',
        client: _okClient('hi', model: 'deepseek-flash'),
      );

      final result = await provider.chat(<LlmMessage>[
        const LlmMessage('user', 'hello'),
      ]);

      expect(result.content, 'hi');
      expect(result.provider, 'deepseek');
    });
  });

  group('FallbackLlm', () {
    test('首选成功时不调用备选', () async {
      var fallbackCalled = false;
      final primary = doubaoProviderForTest(
        apiKey: 'k',
        client: _okClient('primary'),
      );
      final fallback = deepseekProviderForTest(
        apiKey: 'k',
        client: MockClient((_) async {
          fallbackCalled = true;
          return http.Response('{}', 200);
        }),
      );

      final llm = FallbackLlm(<LlmProvider>[primary, fallback]);
      final result = await llm.chat(<LlmMessage>[
        const LlmMessage('user', 'hi'),
      ]);

      expect(result.content, 'primary');
      expect(fallbackCalled, isFalse);
    });

    test('首选失败时回退到备选', () async {
      final primary = doubaoProviderForTest(
        apiKey: 'k',
        client: _errClient(500, 'server error'),
      );
      final fallback = deepseekProviderForTest(
        apiKey: 'k',
        client: _okClient('fallback ok'),
      );

      final llm = FallbackLlm(<LlmProvider>[primary, fallback]);
      final result = await llm.chat(<LlmMessage>[
        const LlmMessage('user', 'hi'),
      ]);

      expect(result.content, 'fallback ok');
      expect(result.provider, 'deepseek');
    });

    test('全部失败时抛出汇总异常', () async {
      final primary = doubaoProviderForTest(
        apiKey: 'k',
        client: _errClient(500, 'a'),
      );
      final fallback = deepseekProviderForTest(
        apiKey: 'k',
        client: _errClient(500, 'b'),
      );

      final llm = FallbackLlm(<LlmProvider>[primary, fallback]);

      expect(
        () => llm.chat(<LlmMessage>[const LlmMessage('user', 'hi')]),
        throwsA(isA<LlmException>()),
      );
    });
  });

  group('Responses 形态', () {
    test('chat 走流式：端点、载荷与解析', () async {
      late http.Request captured;
      final provider = doubaoProviderForTest(
        apiKey: 'k',
        apiStyle: LlmApiStyle.responses,
        client: MockClient((http.Request request) async {
          captured = request;
          return http.Response(
            'data: {"type":"response.output_text.delta","delta":"你"}\n\n'
            'data: {"type":"response.output_text.delta","delta":"好"}\n\n'
            'data: {"type":"response.completed","response":{"status":"completed",'
            '"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}\n\n',
            200,
            headers: <String, String>{
              'content-type': 'text/event-stream; charset=utf-8',
            },
          );
        }),
      );

      final result = await provider.chat(<LlmMessage>[
        const LlmMessage('system', 'sys'),
        const LlmMessage('assistant', 'prev'),
        const LlmMessage('user', 'hi'),
      ]);

      expect(result.content, '你好');
      expect(result.provider, 'doubao');
      expect(result.usage['total_tokens'], 3);
      expect(captured.url.path, endsWith('/responses'));

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['stream'], isTrue);
      expect(body['store'], isFalse);
      expect(body.containsKey('messages'), isFalse);
      final input = body['input'] as List<dynamic>;
      expect(input, hasLength(3));
      final assistant = input[1] as Map<String, dynamic>;
      expect(assistant['type'], 'message');
      expect(assistant['status'], 'completed');
      expect(
        assistant['content'],
        <dynamic>[
          <String, dynamic>{'type': 'output_text', 'text': 'prev'},
        ],
      );
    });

    test('流式：增量、思考与终态用量', () async {
      final provider = doubaoProviderForTest(
        apiKey: 'k',
        apiStyle: LlmApiStyle.responses,
        client: _sseClient(
          'data: {"type":"response.output_text.delta","delta":"你"}\n\n'
          'data: {"type":"response.reasoning_summary_text.delta","delta":"想"}\n\n'
          'data: {"type":"response.output_text.delta","delta":"好"}\n\n'
          'data: {"type":"response.completed","response":{"status":"completed",'
          '"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}\n\n',
        ),
      );

      final events = await provider
          .chatStream(<LlmMessage>[const LlmMessage('user', 'hi')]).toList();

      expect(events.whereType<LlmTextDelta>().map((e) => e.text).join(), '你好');
      expect(events.whereType<LlmReasoningDelta>().single.text, '想');
      final done = events.whereType<LlmStreamDone>().single;
      expect(done.finishReason, 'completed');
      expect(done.usage['total_tokens'], 3);
    });
  });

  group('流式 — Chat Completions', () {
    test('增量、结束原因与用量', () async {
      final provider = doubaoProviderForTest(
        apiKey: 'k',
        client: _sseClient(
          'data: {"choices":[{"delta":{"content":"你"},"finish_reason":null}]}\n\n'
          'data: {"choices":[{"delta":{"content":"好"},"finish_reason":null}]}\n\n'
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
          'data: {"choices":[],"usage":{"prompt_tokens":1,"completion_tokens":2,'
          '"total_tokens":3}}\n\n'
          'data: [DONE]\n\n',
        ),
      );

      final events = await provider
          .chatStream(<LlmMessage>[const LlmMessage('user', 'hi')]).toList();

      expect(events.whereType<LlmTextDelta>().map((e) => e.text).join(), '你好');
      final done = events.whereType<LlmStreamDone>().single;
      expect(done.finishReason, 'stop');
      expect(done.usage['total_tokens'], 3);
    });
  });

  group('FallbackLlm 流式', () {
    test('首选失败时回退到备选', () async {
      final primary = doubaoProviderForTest(
        apiKey: 'k',
        client: _errClient(500, 'server error'),
      );
      final fallback = deepseekProviderForTest(
        apiKey: 'k',
        client: _sseClient(
          'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
        ),
      );

      final llm = FallbackLlm(<LlmProvider>[primary, fallback]);
      final events = await llm
          .chatStream(<LlmMessage>[const LlmMessage('user', 'hi')]).toList();

      expect(events.whereType<LlmTextDelta>().single.text, 'ok');
      expect(events.whereType<LlmStreamDone>().single.finishReason, 'stop');
    });

    test('首选成功时不调用备选', () async {
      var fallbackCalled = false;
      final primary = doubaoProviderForTest(
        apiKey: 'k',
        client: _sseClient(
          'data: {"choices":[{"delta":{"content":"primary"},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
        ),
      );
      final fallback = deepseekProviderForTest(
        apiKey: 'k',
        client: MockClient((_) async {
          fallbackCalled = true;
          return http.Response('data: [DONE]\n\n', 200);
        }),
      );

      final llm = FallbackLlm(<LlmProvider>[primary, fallback]);
      await llm
          .chatStream(<LlmMessage>[const LlmMessage('user', 'hi')]).toList();

      expect(fallbackCalled, isFalse);
    });
  });

  group('provideLlm', () {
    test('将 FallbackLlm 注册为服务', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);

      provideLlm(ctx, llm: FallbackLlm(const <LlmProvider>[]));

      expect(ctx.has('llm'), isTrue);
      expect(ctx.get<FallbackLlm>('llm'), isA<FallbackLlm>());
    });
  });
}
