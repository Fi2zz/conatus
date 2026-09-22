import 'dart:convert';
import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('解析 web.results[].description，携带 X-Subscription-Token 与查询参数',
      () async {
    http.Request? captured;
    final BraveSearchProvider provider = BraveSearchProvider(
      apiKey: 'brave-secret',
      client: MockClient((http.Request request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'web': <String, Object?>{
              'results': <Object?>[
                <String, Object?>{
                  'title': 'T',
                  'url': 'https://b.com',
                  'description': 'Hello <strong>world</strong> &amp; more',
                },
              ],
            },
          }),
          200,
        );
      }),
    );

    final List<SearchResult> results = await provider.search('天气', limit: 3);

    expect(provider.name, 'brave');
    expect(results.single.title, 'T');
    expect(results.single.url, 'https://b.com');
    expect(results.single.snippet, 'Hello world & more');
    expect(captured!.headers['x-subscription-token'], 'brave-secret');
    expect(captured!.url.path, '/res/v1/web/search');
    expect(captured!.url.queryParameters['q'], '天气');
    expect(captured!.url.queryParameters['count'], '3');
  });

  test('web 缺失返回空列表', () async {
    final BraveSearchProvider provider = BraveSearchProvider(
      apiKey: 'k',
      client: MockClient(
          (http.Request request) async => http.Response('{"type": "search"}', 200)),
    );

    expect(await provider.search('q'), isEmpty);
  });

  test('count 超过 20 时钳到 20', () async {
    http.Request? captured;
    final BraveSearchProvider provider = BraveSearchProvider(
      apiKey: 'k',
      client: MockClient((http.Request request) async {
        captured = request;
        return http.Response('{"web": {"results": []}}', 200);
      }),
    );

    await provider.search('q', limit: 100);

    expect(captured!.url.queryParameters['count'], '20');
  });

  test('非 200 抛 SearchException', () async {
    final BraveSearchProvider provider = BraveSearchProvider(
      apiKey: 'k',
      client: MockClient(
          (http.Request request) async => http.Response('{}', 429)),
    );

    await expectLater(
      provider.search('q'),
      throwsA(isA<SearchException>().having(
        (SearchException e) => e.message,
        'message',
        'brave HTTP 429',
      )),
    );
  });
}
