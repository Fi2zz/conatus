import 'dart:convert';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const List<Map<String, dynamic>> _tools = <Map<String, dynamic>>[
  <String, dynamic>{
    'name': 'get_time',
    'description': '返回当前时间',
    'parameters': <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{}
    },
  },
];

void main() {
  group('Chat Completions function calling', () {
    test('下发 tools 并解析 tool_calls', () async {
      http.Request? captured;
      final DoubaoProvider provider = DoubaoProvider(
        apiKey: 'k',
        baseUrl: 'https://x',
        model: 'm',
        client: MockClient((http.Request request) async {
          captured = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'model': 'm',
              'choices': <Object?>[
                <String, Object?>{
                  'message': <String, Object?>{
                    'role': 'assistant',
                    'content': '',
                    'tool_calls': <Object?>[
                      <String, Object?>{
                        'id': 'call_1',
                        'type': 'function',
                        'function': <String, Object?>{
                          'name': 'get_time',
                          'arguments': '{"tz":"utc"}',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final LlmResult result = await provider.chat(
        <LlmMessage>[const LlmMessage('user', '现在几点')],
        tools: _tools,
      );

      final Map<String, Object?> body =
          jsonDecode(captured!.body) as Map<String, Object?>;
      final List<Object?> sentTools = body['tools']! as List<Object?>;
      expect((sentTools.single! as Map<String, Object?>)['type'], 'function');
      final Map<String, Object?> function = (sentTools.single!
          as Map<String, Object?>)['function']! as Map<String, Object?>;
      expect(function['name'], 'get_time');

      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.id, 'call_1');
      expect(result.toolCalls.single.name, 'get_time');
      expect(result.toolCalls.single.arguments, '{"tz":"utc"}');
    });

    test('助手工具调用与工具结果消息正确序列化', () async {
      http.Request? captured;
      final DoubaoProvider provider = DoubaoProvider(
        apiKey: 'k',
        baseUrl: 'https://x',
        model: 'm',
        client: MockClient((http.Request request) async {
          captured = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'model': 'm',
              'choices': <Object?>[
                <String, Object?>{
                  'message': <String, Object?>{
                    'role': 'assistant',
                    'content': 'done'
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      await provider.chat(<LlmMessage>[
        const LlmMessage('user', '现在几点'),
        const LlmMessage('assistant', '', toolCalls: <LlmToolCall>[
          LlmToolCall(id: 'call_1', name: 'get_time'),
        ]),
        const LlmMessage('tool', '12:00', toolCallId: 'call_1'),
      ]);

      final Map<String, Object?> body =
          jsonDecode(captured!.body) as Map<String, Object?>;
      final List<Object?> messages = body['messages']! as List<Object?>;
      final Map<String, Object?> assistant =
          messages[1]! as Map<String, Object?>;
      expect((assistant['tool_calls']! as List<Object?>).single,
          isA<Map<String, Object?>>());
      final Map<String, Object?> toolMsg = messages[2]! as Map<String, Object?>;
      expect(toolMsg['role'], 'tool');
      expect(toolMsg['tool_call_id'], 'call_1');
      expect(toolMsg['content'], '12:00');
    });
  });

  group('Responses function calling', () {
    test('下发 tools 并解析 function_call', () async {
      http.Request? captured;
      final DoubaoProvider provider = DoubaoProvider(
        apiKey: 'k',
        baseUrl: 'https://x',
        model: 'm',
        apiStyle: LlmApiStyle.responses,
        client: MockClient((http.Request request) async {
          captured = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'model': 'm',
              'output': <Object?>[
                <String, Object?>{
                  'type': 'function_call',
                  'call_id': 'call_9',
                  'name': 'get_time',
                  'arguments': '{"x":1}',
                },
              ],
            }),
            200,
          );
        }),
      );

      final LlmResult result = await provider.chat(
        <LlmMessage>[const LlmMessage('user', 'hi')],
        tools: _tools,
      );

      final Map<String, Object?> body =
          jsonDecode(captured!.body) as Map<String, Object?>;
      final Map<String, Object?> tool =
          (body['tools']! as List<Object?>).single! as Map<String, Object?>;
      expect(tool['type'], 'function');
      expect(tool['name'], 'get_time');
      expect(tool.containsKey('function'), isFalse);

      expect(result.toolCalls.single.id, 'call_9');
      expect(result.toolCalls.single.arguments, '{"x":1}');
    });

    test('工具结果序列化为 function_call_output', () async {
      http.Request? captured;
      final DoubaoProvider provider = DoubaoProvider(
        apiKey: 'k',
        baseUrl: 'https://x',
        model: 'm',
        apiStyle: LlmApiStyle.responses,
        client: MockClient((http.Request request) async {
          captured = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'model': 'm',
              'output': <Object?>[
                <String, Object?>{
                  'type': 'message',
                  'content': <Object?>[
                    <String, Object?>{'type': 'output_text', 'text': 'ok'},
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );

      final LlmResult result = await provider.chat(<LlmMessage>[
        const LlmMessage('assistant', '', toolCalls: <LlmToolCall>[
          LlmToolCall(id: 'c1', name: 'get_time'),
        ]),
        const LlmMessage('tool', '12:00', toolCallId: 'c1'),
      ]);

      final Map<String, Object?> body =
          jsonDecode(captured!.body) as Map<String, Object?>;
      final List<Object?> input = body['input']! as List<Object?>;
      expect((input[0]! as Map<String, Object?>)['type'], 'function_call');
      expect(
          (input[1]! as Map<String, Object?>)['type'], 'function_call_output');
      expect((input[1]! as Map<String, Object?>)['output'], '12:00');
      expect(result.content, 'ok');
    });
  });
}
