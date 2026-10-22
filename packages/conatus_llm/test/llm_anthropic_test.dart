/// Anthropic Messages wire：请求映射、认证头与 SSE 解析。
library;

import 'dart:convert';

import 'package:conatus_llm/conatus_llm.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const List<LlmMessage> _messages = <LlmMessage>[
  LlmMessage('system', '你是助手'),
  LlmMessage('user', '看下这个文件'),
];

const String _textAndToolSse = '''
event: message_start
data: {"type":"message_start","message":{"model":"claude-haiku-5-5","usage":{"input_tokens":12}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"我先读文件"}}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"read_file","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"path\\":"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\\"a.txt\\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":7}}

event: message_stop
data: {"type":"message_stop"}
''';

class _Recorder {
  final List<http.Request> requests = <http.Request>[];

  MockClient client(String body) => MockClient((http.Request request) async {
        requests.add(request);
        return http.Response.bytes(
          utf8.encode(body),
          200,
          headers: <String, String>{
            'content-type': 'text/event-stream; charset=utf-8',
          },
        );
      });
}

void main() {
  test('请求：system 抽取、工具映射、max_tokens 缺省与认证头', () async {
    final _Recorder recorder = _Recorder();
    final AnthropicProvider provider = AnthropicProvider(
      name: 'anthropic',
      baseUrl: 'https://api.anthropic.com/v1',
      model: 'claude-haiku-5-5',
      apiKey: 'sk-ant',
      client: recorder.client(_textAndToolSse),
    );

    final LlmResult result = await provider.chat(
      <LlmMessage>[
        ..._messages,
        const LlmMessage('assistant', '', toolCalls: <LlmToolCall>[
          LlmToolCall(id: 'toolu_0', name: 'read_file', arguments: '{"path":"b.txt"}'),
        ]),
        const LlmMessage('tool', '文件内容', toolCallId: 'toolu_0'),
      ],
      tools: <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'read_file',
          'description': '读文件',
          'parameters': <String, dynamic>{'type': 'object'},
        },
      ],
    );

    final http.Request request = recorder.requests.single;
    expect(request.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(request.headers['x-api-key'], 'sk-ant');
    expect(request.headers['anthropic-version'], '2023-06-01');
    expect(request.headers.containsKey('authorization'), isFalse);

    final Map<String, dynamic> body =
        jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['system'], '你是助手');
    expect(body['max_tokens'], 4096);
    expect(body['stream'], isTrue);
    final List<dynamic> tools = body['tools'] as List<dynamic>;
    expect((tools.single as Map<String, dynamic>)['input_schema'], isNotNull);

    final List<dynamic> messages = body['messages'] as List<dynamic>;
    expect(messages.length, 3); // user / assistant(tool_use) / user(tool_result)
    final Map<String, dynamic> assistant =
        messages[1] as Map<String, dynamic>;
    expect(
      (assistant['content'] as List<dynamic>)
          .any((dynamic block) => (block as Map<String, dynamic>)['type'] == 'tool_use'),
      isTrue,
    );
    final Map<String, dynamic> toolResult =
        messages[2] as Map<String, dynamic>;
    final Map<String, dynamic> resultBlock =
        (toolResult['content'] as List<dynamic>).single as Map<String, dynamic>;
    expect(resultBlock['type'], 'tool_result');
    expect(resultBlock['tool_use_id'], 'toolu_0');

    expect(result.content, '我先读文件');
    expect(result.toolCalls.single.name, 'read_file');
    expect(result.toolCalls.single.arguments, '{"path":"a.txt"}');
    expect(result.usage['input_tokens'], 12);
    expect(result.usage['output_tokens'], 7);
  });

  test('OpenCode 主机用 Bearer，并合并动态会话头', () async {
    final _Recorder recorder = _Recorder();
    final AnthropicProvider provider = AnthropicProvider(
      name: 'opencode-go-anthropic',
      baseUrl: 'https://opencode.ai/inference/go/anthropic/v1',
      model: 'claude-haiku-5-5',
      apiKey: 'oc_sk',
      headersProvider: () => <String, String>{
        'x-opencode-session': 'ses_abc',
      },
      client: recorder.client(_textAndToolSse),
    );

    await provider.chat(_messages);

    final http.Request request = recorder.requests.single;
    expect(request.headers['authorization'], 'Bearer oc_sk');
    expect(request.headers.containsKey('x-api-key'), isFalse);
    expect(request.headers['x-opencode-session'], 'ses_abc');
    expect(request.headers['user-agent'], 'nava/0.1.0');
  });

  test('max_tokens 可由 options 覆盖', () async {
    final _Recorder recorder = _Recorder();
    final AnthropicProvider provider = AnthropicProvider(
      name: 'anthropic',
      baseUrl: 'https://api.anthropic.com/v1',
      model: 'm',
      apiKey: 'k',
      client: recorder.client(_textAndToolSse),
    );

    await provider.chat(_messages, options: <String, dynamic>{
      'max_tokens': 1024,
    });

    final Map<String, dynamic> body =
        jsonDecode(recorder.requests.single.body) as Map<String, dynamic>;
    expect(body['max_tokens'], 1024);
  });

  test('HTTP 错误转 LlmException', () async {
    final AnthropicProvider provider = AnthropicProvider(
      name: 'anthropic',
      baseUrl: 'https://api.anthropic.com/v1',
      model: 'm',
      apiKey: 'k',
      client: MockClient((http.Request request) async =>
          http.Response('{"error":{"message":"bad key"}}', 401)),
    );

    expect(
      () => provider.chat(_messages),
      throwsA(isA<LlmException>()
          .having((LlmException e) => e.statusCode, 'statusCode', 401)
          .having((LlmException e) => e.message, 'message', 'bad key')),
    );
  });
}
