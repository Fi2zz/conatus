import 'dart:convert';
import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('解析 results，并携带 API Key', () async {
    http.Request? captured;
    final ExaSearchProvider provider = ExaSearchProvider(
      apiKey: 'secret',
      client: MockClient((http.Request request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'results': <Object?>[
              <String, Object?>{
                'title': 'T',
                'url': 'https://e.com',
                'text': 'S'
              },
              <String, Object?>{'title': 'T2', 'url': 'https://e2.com'},
            ],
          }),
          200,
        );
      }),
    );

    final List<SearchResult> results = await provider.search('query', limit: 3);

    expect(provider.name, 'exa');
    expect(results, hasLength(2));
    expect(results.first.title, 'T');
    expect(results.first.snippet, 'S');
    expect(captured!.headers['x-api-key'], 'secret');
    final Map<String, Object?> body =
        jsonDecode(captured!.body) as Map<String, Object?>;
    expect(body['query'], 'query');
    expect(body['numResults'], 3);
  });

  test('非 200 抛 SearchException', () async {
    final ExaSearchProvider provider = ExaSearchProvider(
      apiKey: 'k',
      client:
          MockClient((http.Request request) async => http.Response('{}', 401)),
    );

    await expectLater(provider.search('q'), throwsA(isA<SearchException>()));
  });
}
