import 'dart:convert';
import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('解析 results[].content，携带 Bearer 与 max_results', () async {
    http.Request? captured;
    final TavilySearchProvider provider = TavilySearchProvider(
      apiKey: 'tvly-secret',
      client: MockClient((http.Request request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'results': <Object?>[
              <String, Object?>{
                'title': 'T',
                'url': 'https://t.com',
                'content': 'C',
              },
              <String, Object?>{'title': 'T2', 'url': 'https://t2.com'},
            ],
          }),
          200,
        );
      }),
    );

    final List<SearchResult> results = await provider.search('query', limit: 3);

    expect(provider.name, 'tavily');
    expect(results, hasLength(2));
    expect(results.first.title, 'T');
    expect(results.first.url, 'https://t.com');
    expect(results.first.snippet, 'C');
    expect(captured!.headers['authorization'], 'Bearer tvly-secret');
    expect(captured!.url.path, '/search');
    final Map<String, Object?> body =
        jsonDecode(captured!.body) as Map<String, Object?>;
    expect(body['query'], 'query');
    expect(body['max_results'], 3);
    expect(body['search_depth'], 'basic');
  });

  test('limit 超过 20 时钳到 20', () async {
    http.Request? captured;
    final TavilySearchProvider provider = TavilySearchProvider(
      apiKey: 'k',
      client: MockClient((http.Request request) async {
        captured = request;
        return http.Response('{"results": []}', 200);
      }),
    );

    await provider.search('q', limit: 100);

    final Map<String, Object?> body =
        jsonDecode(captured!.body) as Map<String, Object?>;
    expect(body['max_results'], 20);
  });

  test('results 缺失返回空列表', () async {
    final TavilySearchProvider provider = TavilySearchProvider(
      apiKey: 'k',
      client: MockClient(
          (http.Request request) async => http.Response('{"query": "q"}', 200)),
    );

    expect(await provider.search('q'), isEmpty);
  });

  test('非 200 抛 SearchException', () async {
    final TavilySearchProvider provider = TavilySearchProvider(
      apiKey: 'k',
      client: MockClient(
          (http.Request request) async => http.Response('{}', 401)),
    );

    await expectLater(
      provider.search('q'),
      throwsA(isA<SearchException>().having(
        (SearchException e) => e.message,
        'message',
        'tavily HTTP 401',
      )),
    );
  });
}
