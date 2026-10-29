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
  test('解析 search_results[]，携带 Bearer / limit / include_content=false',
      () async {
    http.Request? captured;
    final KimiSearchProvider provider = KimiSearchProvider(
      apiKey: 'sk-kimi',
      client: MockClient((http.Request request) async {
        captured = request;
        return _json(jsonEncode(<String, Object?>{
          'search_results': <Object?>[
            <String, Object?>{
              'title': 'Kimi K3',
              'url': 'https://e.com/k3',
              'snippet': '短摘要',
              'text': '正文',
              'site_name': 'example',
            },
            <String, Object?>{'title': 'T2', 'url': 'https://e.com/2'},
          ],
        }));
      }),
    );

    final List<SearchResult> results = await provider.search('q', limit: 3);

    expect(provider.name, 'kimi');
    expect(results, hasLength(2));
    expect(results.first.title, 'Kimi K3');
    expect(results.first.url, 'https://e.com/k3');
    expect(results.first.snippet, '短摘要');
    expect(results.last.snippet, '');
    expect(captured!.url.toString(), '$kKimiBaseUrl/v1/tools/search');
    expect(captured!.headers['authorization'], 'Bearer sk-kimi');
    final Map<String, Object?> body =
        jsonDecode(captured!.body) as Map<String, Object?>;
    expect(body['text_query'], 'q');
    expect(body['limit'], 3);
    expect(body['include_content'], isFalse);
    expect(body['timeout_seconds'], 20);
  });

  test('snippet 缺失或空白时回退 text', () async {
    final KimiSearchProvider provider = KimiSearchProvider(
      apiKey: 'k',
      client: MockClient((_) async => _json(jsonEncode(<String, Object?>{
            'search_results': <Object?>[
              <String, Object?>{'text': '正文兜底'},
              <String, Object?>{'snippet': '   ', 'text': '空白兜底'},
            ],
          }))),
    );

    final List<SearchResult> results = await provider.search('q');

    expect(
        results.map((SearchResult r) => r.snippet), <String>['正文兜底', '空白兜底']);
  });

  test('超长摘要截断并加省略号', () async {
    final KimiSearchProvider provider = KimiSearchProvider(
      apiKey: 'k',
      client: MockClient((_) async => _json(jsonEncode(<String, Object?>{
            'search_results': <Object?>[
              <String, Object?>{'snippet': 'x' * (kKimiSnippetLimit + 40)},
            ],
          }))),
    );

    final String snippet = (await provider.search('q')).single.snippet;

    expect(snippet.length, kKimiSnippetLimit + 1);
    expect(snippet.endsWith('…'), isTrue);
  });

  test('limit 钳在 1..20，timeout_seconds 随构造超时变化', () async {
    final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];
    final KimiSearchProvider provider = KimiSearchProvider(
      apiKey: 'k',
      timeout: const Duration(seconds: 40),
      client: MockClient((http.Request request) async {
        bodies.add(jsonDecode(request.body) as Map<String, Object?>);
        return _json('{"search_results": []}');
      }),
    );

    await provider.search('q', limit: 0);
    await provider.search('q', limit: 500);

    expect(bodies.map((Map<String, Object?> b) => b['limit']),
        <int>[1, kKimiSearchMaxCount]);
    expect(bodies.every((Map<String, Object?> b) => b['timeout_seconds'] == 40),
        isTrue);
  });

  test('超长本地超时被钳到上游上限', () async {
    late Map<String, Object?> sent;
    final KimiSearchProvider provider = KimiSearchProvider(
      apiKey: 'k',
      timeout: const Duration(seconds: 120),
      client: MockClient((http.Request request) async {
        sent = jsonDecode(request.body) as Map<String, Object?>;
        return _json('{"search_results": []}');
      }),
    );

    await provider.search('q');

    expect(sent['timeout_seconds'], kKimiSearchMaxTimeoutSeconds);
  });

  test('search_results 缺失或非列表返回空列表', () async {
    for (final String body in <String>['{"search_results": null}', '{}']) {
      final KimiSearchProvider provider = KimiSearchProvider(
        apiKey: 'k',
        client: MockClient((_) async => _json(body)),
      );

      expect(await provider.search('q'), isEmpty, reason: body);
    }
  });

  test('非 200 抛 SearchException 并带 error.message', () async {
    final KimiSearchProvider provider = KimiSearchProvider(
      apiKey: 'k',
      client: MockClient((_) async => _json(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{'message': 'rate limit exceeded'},
            }),
            429,
          )),
    );

    await expectLater(
      provider.search('q'),
      throwsA(isA<SearchException>().having(
        (SearchException e) => e.message,
        'message',
        'kimi HTTP 429：rate limit exceeded',
      )),
    );
  });

  test('非 JSON 响应抛 SearchException', () async {
    final KimiSearchProvider provider = KimiSearchProvider(
      apiKey: 'k',
      client: MockClient((_) async => http.Response('<html>502</html>', 200)),
    );

    await expectLater(
      provider.search('q'),
      throwsA(isA<SearchException>().having(
          (SearchException e) => e.message, 'message', 'kimi 返回了非对象 JSON')),
    );
  });

  test('请求超时归一成 SearchException', () async {
    final KimiSearchProvider provider = KimiSearchProvider(
      apiKey: 'k',
      timeout: const Duration(milliseconds: 10),
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return _json('{"search_results": []}');
      }),
    );

    await expectLater(
      provider.search('q'),
      throwsA(isA<SearchException>().having(
          (SearchException e) => e.message, 'message', contains('kimi 请求超时'))),
    );
  });
}
