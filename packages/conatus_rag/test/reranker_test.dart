import 'dart:convert';

import 'package:conatus_rag/conatus_rag.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'helpers/fixtures.dart';

void main() {
  group('HttpReranker', () {
    test('保留余弦分，重排分写入 rerankScore', () async {
      final MockClient mockClient = MockClient((Request request) async {
        return Response(
          jsonEncode(<String, Object?>{
            'results': <Map<String, Object?>>[
              <String, Object?>{'index': 1, 'relevance_score': 0.95},
              <String, Object?>{'index': 0, 'relevance_score': 0.85},
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final HttpReranker reranker = HttpReranker(
        baseUrl: 'https://api.example.com',
        model: 'rerank-model',
        apiKey: 'test-key',
        client: mockClient,
      );

      final List<RagHit> candidates = <RagHit>[
        RagHit(chunk: chunk('a', 't1', <String>{'tag'}, 0), score: 0.75),
        RagHit(chunk: chunk('b', 't1', <String>{'tag'}, 1), score: 0.82),
      ];

      final List<RagHit> reranked = await reranker.rerank(
        'query',
        candidates,
        topK: 2,
      );

      expect(reranked.length, 2);
      expect(reranked[0].chunk.id, 'b');
      expect(reranked[0].score, 0.82);
      expect(reranked[0].rerankScore, 0.95);
      expect(reranked[1].chunk.id, 'a');
      expect(reranked[1].score, 0.75);
      expect(reranked[1].rerankScore, 0.85);

      reranker.dispose();
    });
  });
}
