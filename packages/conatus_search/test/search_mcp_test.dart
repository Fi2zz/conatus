import 'dart:convert';
import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// 把一条 JSON-RPC 结果包成 SSE 正文（Exa / Parallel 的实际返回形态）。
String _sse(Map<String, Object?> message) =>
    'event: message\ndata: ${jsonEncode(message)}\n\n';

/// 构造带 UTF-8 声明的响应（`http.Response` 默认按 latin1 编码正文）。
http.Response _jsonResponse(String body) => http.Response(
      body,
      200,
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );

void main() {
  group('McpSearchProvider 请求形态', () {
    test('直连 tools/call，不走握手，Accept 含 event-stream', () async {
      http.Request? captured;
      final McpSearchProvider provider = McpSearchProvider(
        profile: kParallelSearchProfile,
        client: MockClient((http.Request request) async {
          captured = request;
          return _jsonResponse(
            _sse(<String, Object?>{
              'jsonrpc': '2.0',
              'id': 1,
              'result': <String, Object?>{
                'structuredContent': <String, Object?>{
                  'results': <Object?>[
                    <String, Object?>{
                      'title': 'Dart',
                      'url': 'https://dart.dev',
                      'excerpts': <Object?>['快速、可移植'],
                    },
                  ],
                },
              },
            }),
          );
        }),
      );

      final List<SearchResult> results = await provider.search('dart', limit: 3);

      expect(captured!.url.toString(), kParallelMcpEndpoint);
      expect(captured!.headers['accept'], contains('text/event-stream'));
      final Map<String, Object?> body =
          jsonDecode(captured!.body) as Map<String, Object?>;
      expect(body['method'], 'tools/call');
      final Map<String, Object?> params =
          body['params'] as Map<String, Object?>;
      expect(params['name'], kParallelSearchTool);
      expect(results.single.title, 'Dart');
      expect(results.single.url, 'https://dart.dev');
      expect(results.single.snippet, '快速、可移植');
    });

    test('非 200 抛 SearchException 且带状态码', () async {
      final McpSearchProvider provider = McpSearchProvider(
        profile: kParallelSearchProfile,
        client: MockClient((_) async => http.Response('boom', 502)),
      );

      await expectLater(
        provider.search('q'),
        throwsA(isA<SearchException>().having(
            (SearchException e) => e.toString(), 'message', contains('502'))),
      );
    });

    test('工具报错（isError）转成异常，交给回退链', () async {
      final McpSearchProvider provider = McpSearchProvider(
        profile: kParallelSearchProfile,
        client: MockClient((_) async => _jsonResponse(
              _sse(<String, Object?>{
                'jsonrpc': '2.0',
                'id': 1,
                'result': <String, Object?>{
                  'isError': true,
                  'content': <Object?>[
                    <String, Object?>{'type': 'text', 'text': 'rate limited'},
                  ],
                },
              }),
            )),
      );

      await expectLater(
        provider.search('q'),
        throwsA(isA<SearchException>().having((SearchException e) => '$e',
            'message', contains('rate limited'))),
      );
    });

    test('结果超过 limit 时截断（Parallel 无条数参数）', () async {
      final McpSearchProvider provider = McpSearchProvider(
        profile: kParallelSearchProfile,
        client: MockClient((_) async => _jsonResponse(
              _sse(<String, Object?>{
                'jsonrpc': '2.0',
                'id': 1,
                'result': <String, Object?>{
                  'structuredContent': <String, Object?>{
                    'results': <Object?>[
                      for (int i = 0; i < 5; i++)
                        <String, Object?>{
                          'title': 'T$i',
                          'url': 'https://e.com/$i',
                        },
                    ],
                  },
                },
              }),
            )),
      );

      expect(await provider.search('q', limit: 2), hasLength(2));
    });
  });

  group('响应解码', () {
    test('SSE 多帧取第一条 JSON-RPC 消息', () {
      final Map<String, Object?>? decoded = decodeMcpResponseBody(
        'event: message\n'
        'data: {"jsonrpc":"2.0","id":1,"result":{}}\n'
        '\n'
        'data: {"jsonrpc":"2.0","id":2,"result":{"later":true}}\n',
      );

      expect(decoded!['id'], 1);
    });

    test('纯 JSON 正文可直接解码', () {
      final Map<String, Object?>? decoded = decodeMcpResponseBody(
        '{"jsonrpc":"2.0","id":1,"result":{"ok":true}}',
      );

      expect((decoded!['result']! as Map<String, Object?>)['ok'], isTrue);
    });

    test('无法解析时返回 null', () {
      expect(decodeMcpResponseBody('<html>502</html>'), isNull);
    });

    test('structuredContent 缺失时把 content 文本当 JSON 解析', () {
      final Map<String, Object?>? structured = mcpStructuredResult(
        <String, Object?>{
          'content': <Object?>[
            <String, Object?>{
              'type': 'text',
              'text': '{"results":[{"title":"A"}]}',
            },
          ],
        },
      );

      expect(structured!['results'], isA<List<Object?>>());
    });
  });

  group('Parallel 结果解码', () {
    test('excerpts 列表拼接成摘要，缺失字段降级为空串', () {
      final List<SearchResult> results = decodeParallelResults(
        <String, Object?>{
          'structuredContent': <String, Object?>{
            'results': <Object?>[
              <String, Object?>{
                'title': 'A',
                'url': 'https://a.com',
                'excerpts': <Object?>['第一段', '第二段'],
              },
              <String, Object?>{},
            ],
          },
        },
      );

      expect(results, hasLength(2));
      expect(results.first.snippet, '第一段\n第二段');
      expect(results.last.title, '');
      expect(results.last.url, '');
    });

    test('超长摘要截断并加省略号', () {
      final List<SearchResult> results = decodeParallelResults(
        <String, Object?>{
          'structuredContent': <String, Object?>{
            'results': <Object?>[
              <String, Object?>{
                'title': 'A',
                'url': 'https://a.com',
                'excerpts': <Object?>['x' * (kParallelSnippetLimit + 50)],
              },
            ],
          },
        },
      );

      final String snippet = results.single.snippet;
      expect(snippet.length, kParallelSnippetLimit + 1);
      expect(snippet.endsWith('…'), isTrue);
    });

    test('structuredContent 为空时返回空列表（不抛错）', () {
      expect(decodeParallelResults(const <String, Object?>{}), isEmpty);
    });
  });

  group('Exa 文本结果解码', () {
    test('按 Title/URL 成对切块，元数据行不进摘要', () {
      final Map<String, Object?> payload = <String, Object?>{
        'content': <Object?>[
          <String, Object?>{
            'type': 'text',
            'text': 'Title: Sound null safety\n'
                'URL: https://dart.dev/null-safety\n'
                'Published: 2026-02-26T00:00:00.000Z\n'
                'Author: N/A\n'
                'Highlights:\n'
                'Dart 默认空安全。\n'
                'Title: Records\n'
                'URL: https://dart.dev/records\n'
                'Highlights:\n'
                '匿名聚合值。\n',
          },
        ],
      };

      final List<SearchResult> results = decodeExaMcpResults(payload);

      expect(results.map((SearchResult r) => r.url),
          <String>['https://dart.dev/null-safety', 'https://dart.dev/records']);
      expect(results.first.title, 'Sound null safety');
      expect(results.first.snippet, 'Dart 默认空安全。');
      expect(results.first.snippet, isNot(contains('Published')));
      expect(results.last.snippet, '匿名聚合值。');
    });

    test('格式完全陌生时返回空列表而不是抛错', () {
      expect(
        decodeExaMcpResults(<String, Object?>{
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'unexpected format'},
          ],
        }),
        isEmpty,
      );
    });

    test('缺少 Title 时用 URL 兜底作标题', () {
      final List<SearchResult> results = decodeExaMcpResults(<String, Object?>{
        'content': <Object?>[
          <String, Object?>{
            'type': 'text',
            'text': 'URL: https://a.com\nHighlights:\n正文\n',
          },
        ],
      });

      expect(results.single.title, 'https://a.com');
    });
  });
}
