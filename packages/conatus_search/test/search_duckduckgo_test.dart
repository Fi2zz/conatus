import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const String _html = '''
<div class="result">
  <a rel="nofollow" class="result__a"
     href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fa&amp;rut=x">Example <b>A</b></a>
  <a class="result__snippet">First &amp; snippet</a>
</div>
<div class="result">
  <a rel="nofollow" class="result__a" href="https://example.org/b">Example B</a>
  <a class="result__snippet">Second</a>
</div>
''';

void main() {
  group('parseDuckDuckGoHtml', () {
    test('解析标题/链接/摘要并解码 uddg 跳转', () {
      final List<SearchResult> results = parseDuckDuckGoHtml(_html);

      expect(results, hasLength(2));
      expect(results[0].title, 'Example A');
      expect(results[0].url, 'https://example.com/a');
      expect(results[0].snippet, 'First & snippet');
      expect(results[1].url, 'https://example.org/b');
    });

    test('limit 截断', () {
      expect(parseDuckDuckGoHtml(_html, limit: 1), hasLength(1));
    });

    test('无结果返回空', () {
      expect(parseDuckDuckGoHtml('<html></html>'), isEmpty);
    });
  });

  group('DuckDuckGoSearchProvider', () {
    test('200 返回解析结果', () async {
      final DuckDuckGoSearchProvider provider = DuckDuckGoSearchProvider(
        client: MockClient(
            (http.Request request) async => http.Response(_html, 200)),
      );

      expect((await provider.search('q')).first.title, 'Example A');
      expect(provider.name, 'duckduckgo');
    });

    test('非 200 抛 SearchException', () async {
      final DuckDuckGoSearchProvider provider = DuckDuckGoSearchProvider(
        client: MockClient(
            (http.Request request) async => http.Response('nope', 503)),
      );

      await expectLater(provider.search('q'), throwsA(isA<SearchException>()));
    });
  });
}
