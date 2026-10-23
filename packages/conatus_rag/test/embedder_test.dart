import 'dart:convert';

import 'package:conatus_rag/conatus_rag.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';

MockClient okClient(List<Map<String, Object?>> seen) =>
    MockClient((Request req) async {
      seen.add(<String, Object?>{
        'url': req.url.toString(),
        'auth': req.headers['Authorization'],
        'body': jsonDecode(req.body),
      });
      final Map<String, Object?> body =
          jsonDecode(req.body) as Map<String, Object?>;
      final List<Object?> input = body['input']! as List<Object?>;
      return Response(
          jsonEncode(<String, Object?>{
            'data': <Map<String, Object?>>[
              for (int i = 0; i < input.length; i++)
                <String, Object?>{
                  'index': i,
                  'embedding': <double>[1, 0]
                },
            ],
          }),
          200);
    });

void main() {
  test('OpenAI 兼容 /embeddings：鉴权、批量切分、解析', () async {
    final List<Map<String, Object?>> seen = <Map<String, Object?>>[];
    final OpenAiEmbedder embedder = OpenAiEmbedder(
        baseUrl: 'https://api.test/v3',
        model: 'm',
        apiKey: 'SECRET',
        dimension: 2,
        batchSize: 2,
        client: okClient(seen));
    final List<List<double>> vectors =
        await embedder.embedBatch(<String>['a', 'b', 'c']);
    expect(vectors, hasLength(3));
    expect(seen, hasLength(2));
    expect(seen.first['url'], 'https://api.test/v3/embeddings');
    expect(seen.first['auth'], 'Bearer SECRET');
    expect(embedder.model, 'm');
  });

  test('维度不符与 401 都抛 rag_embed_failed，消息不含 key', () async {
    final OpenAiEmbedder bad = OpenAiEmbedder(
        baseUrl: 'https://api.test/v3',
        model: 'm',
        apiKey: 'SECRET',
        dimension: 3,
        client: MockClient((Request req) async => Response(
            jsonEncode(<String, Object?>{
              'data': <Map<String, Object?>>[
                <String, Object?>{
                  'index': 0,
                  'embedding': <double>[1, 0]
                },
              ]
            }),
            200)));
    await expectLater(bad.embed('x'), throwsA(isA<RagException>()));
    final OpenAiEmbedder denied = OpenAiEmbedder(
        baseUrl: 'https://api.test/v3',
        model: 'm',
        apiKey: 'SECRET',
        dimension: 2,
        client: MockClient((Request req) async => Response('nope', 401)));
    try {
      await denied.embed('x');
      fail('应当抛错');
    } on RagException catch (e) {
      expect(e.code, 'rag_embed_failed');
      expect(e.message, isNot(contains('SECRET')));
    }
  });

  test('嵌入请求超时抛 rag_embed_failed，消息不含 key', () async {
    final OpenAiEmbedder slow = OpenAiEmbedder(
        baseUrl: 'https://api.test/v3',
        model: 'm',
        apiKey: 'SECRET',
        dimension: 2,
        timeout: const Duration(milliseconds: 10),
        client: MockClient((Request req) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return Response('{}', 200);
        }));
    try {
      await slow.embed('x');
      fail('应当抛错');
    } on RagException catch (e) {
      expect(e.code, 'rag_embed_failed');
      expect(e.message, isNot(contains('SECRET')));
    }
  });
}
