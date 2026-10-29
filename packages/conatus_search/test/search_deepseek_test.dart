import 'dart:convert';
import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// 构造带 UTF-8 声明的响应（`http.Response` 默认按 latin1 编码正文）。
http.Response _json(String body, [int status = 200]) => http.Response(
      body,
      status,
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );

void main() {
  test('解析 results[]，携带 Bearer / count / need_content=false', () async {
    http.Request? captured;
    final DeepSeekSearchProvider provider = DeepSeekSearchProvider(
      apiKey: 'sk-deepseek',
      client: MockClient((http.Request request) async {
        captured = request;
        return _json(jsonEncode(<String, Object?>{
          'results': <Object?>[
            <String, Object?>{
              'title': 'DeepSeek V4',
              'url': 'https://e.com/v4',
              'snippet': '短摘要',
              'summary': '长摘要',
              'content': '正文',
            },
            <String, Object?>{'title': 'T2', 'url': 'https://e.com/2'},
          ],
        }));
      }),
    );

    final List<SearchResult> results = await provider.search('q', limit: 3);

    expect(provider.name, 'deepseek');
    expect(results, hasLength(2));
    expect(results.first.title, 'DeepSeek V4');
    expect(results.first.url, 'https://e.com/v4');
    expect(results.first.snippet, '长摘要');
    expect(results.last.snippet, '');
    expect(captured!.url.toString(), '$kDeepSeekBaseUrl/v1/tools/search');
    expect(captured!.headers['authorization'], 'Bearer sk-deepseek');
    final Map<String, Object?> body =
        jsonDecode(captured!.body) as Map<String, Object?>;
    expect(body['query'], 'q');
    expect(body['count'], 3);
    expect(body['need_content'], isFalse);
  });

  test('summary 缺失或空白时回退 snippet', () async {
    final DeepSeekSearchProvider provider = DeepSeekSearchProvider(
      apiKey: 'k',
      client: MockClient((_) async => _json(jsonEncode(<String, Object?>{
            'results': <Object?>[
              <String, Object?>{'snippet': '短摘要'},
              <String, Object?>{'snippet': '兜底', 'summary': '   '},
            ],
          }))),
    );

    final List<SearchResult> results = await provider.search('q');

    expect(results.map((SearchResult r) => r.snippet), <String>['短摘要', '兜底']);
  });

  test('超长 summary 截断并加省略号', () async {
    final DeepSeekSearchProvider provider = DeepSeekSearchProvider(
      apiKey: 'k',
      client: MockClient((_) async => _json(jsonEncode(<String, Object?>{
            'results': <Object?>[
              <String, Object?>{'summary': 'x' * (kDeepSeekSnippetLimit + 40)},
            ],
          }))),
    );

    final String snippet = (await provider.search('q')).single.snippet;

    expect(snippet.length, kDeepSeekSnippetLimit + 1);
    expect(snippet.endsWith('…'), isTrue);
  });

  test('count 钳在 1..50', () async {
    final List<int> counts = <int>[];
    final DeepSeekSearchProvider provider = DeepSeekSearchProvider(
      apiKey: 'k',
      client: MockClient((http.Request request) async {
        final Map<String, Object?> body =
            jsonDecode(request.body) as Map<String, Object?>;
        counts.add(body['count']! as int);
        return _json('{"results": []}');
      }),
    );

    await provider.search('q', limit: 0);
    await provider.search('q', limit: 500);

    expect(counts, <int>[1, kDeepSeekSearchMaxCount]);
  });

  test('results 缺失或非列表返回空列表', () async {
    for (final String body in <String>['{"results": null}', '{}']) {
      final DeepSeekSearchProvider provider = DeepSeekSearchProvider(
        apiKey: 'k',
        client: MockClient((_) async => _json(body)),
      );

      expect(await provider.search('q'), isEmpty, reason: body);
    }
  });

  test('非 200 抛 SearchException 并带 error.message', () async {
    final DeepSeekSearchProvider provider = DeepSeekSearchProvider(
      apiKey: 'k',
      client: MockClient((_) async => _json(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{'message': 'Insufficient Balance'},
            }),
            402,
          )),
    );

    await expectLater(
      provider.search('q'),
      throwsA(isA<SearchException>().having(
        (SearchException e) => e.message,
        'message',
        'deepseek HTTP 402：Insufficient Balance',
      )),
    );
  });

  test('非 JSON 响应抛 SearchException', () async {
    final DeepSeekSearchProvider provider = DeepSeekSearchProvider(
      apiKey: 'k',
      client: MockClient((_) async => http.Response('<html>502</html>', 200)),
    );

    await expectLater(
      provider.search('q'),
      throwsA(isA<SearchException>().having(
          (SearchException e) => e.message, 'message', 'deepseek 返回了非对象 JSON')),
    );
  });

  test('请求超时归一成 SearchException', () async {
    final DeepSeekSearchProvider provider = DeepSeekSearchProvider(
      apiKey: 'k',
      timeout: const Duration(milliseconds: 10),
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return _json('{"results": []}');
      }),
    );

    await expectLater(
      provider.search('q'),
      throwsA(isA<SearchException>().having((SearchException e) => e.message,
          'message', contains('deepseek 请求超时'))),
    );
  });
}
