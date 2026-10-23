import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_rag/conatus_rag.dart';
import 'package:test/test.dart';

import 'helpers/fixtures.dart';

void main() {
  group('RagSearchTool', () {
    late InMemoryRagBackend backend;
    late RagService service;

    setUp(() async {
      backend = InMemoryRagBackend();
      await backend.upsert(
        <RagChunk>[
          chunk('a', 't1', <String>{'tenant:t1'}, 0, text: '用户：我的订单号是 A-1024'),
          chunk('b', 't1', <String>{'tenant:t1'}, 1, text: '用户：订单 A-1024 已发货'),
        ],
        <List<double>>[
          <double>[1, 0],
          <double>[1, 0],
        ],
      );
      service = RagService(
        backend: backend,
        config: RagConfig(embedder: FakeEmbedder()),
        scopeOf: (String id) async => RagScope(tenantId: 't1'),
      );
    });

    RagSearchTool open() =>
        RagSearchTool(service: service, scope: RagScope(tenantId: 't1'));

    test('schema：名称、风险与参数形状', () {
      final RagSearchTool tool = open();
      expect(tool.name, 'rag_search');
      expect(tool.riskLevel, ToolRisk.low);
      final List<ParamSpec> params = tool.params;
      expect(
        params.map((ParamSpec p) => p.name),
        <String>['query', 'limit', 'session_id', 'from', 'to'],
      );
      expect(params.first.required, isTrue);
      final ParamSpec limit = params[1];
      expect(limit.type, ParamType.integer);
      expect(limit.defaultValue, 5);
    });

    test('无 scope fail closed：不查任何数据', () async {
      final RagSearchTool closed = RagSearchTool(service: service);
      final ToolResult denied = await closed.call(const ToolContext(ToolCall(
          name: 'rag_search', arguments: <String, Object?>{'query': 'x'})));
      expect(denied.isError, isTrue);
      expect(denied.error!.code, 'rag_scope_missing');
      expect((await service.stats()).retrievals, 0);
    });

    test('有 scope 检索返回 citation 与结构化 value', () async {
      final ToolResult hit = await open().call(const ToolContext(ToolCall(
          name: 'rag_search',
          arguments: <String, Object?>{'query': '订单号', 'limit': 99})));
      expect(hit.isError, isFalse);
      expect(hit.content, contains('[相关历史证据]'));
      expect(hit.content, contains('session:s0'));
      final Map<String, Object?> value = hit.value! as Map<String, Object?>;
      expect(value['count'], 2);
      final List<Object?> hits = value['hits']! as List<Object?>;
      expect(hits, hasLength(2));
      final Map<String, Object?> first = hits.first! as Map<String, Object?>;
      expect(
        first.keys,
        containsAll(<String>[
          'id',
          'sourceKind',
          'sourceId',
          'firstSeq',
          'lastSeq',
          'score',
          'startTime',
        ]),
      );
      expect(first['sourceId'], 's0');
      expect(DateTime.parse(first['startTime']! as String).isUtc, isTrue);
    });

    test('limit 夹在 1..15：请求 99 只返回 15 条', () async {
      final InMemoryRagBackend many = InMemoryRagBackend();
      await many.upsert(
        <RagChunk>[
          for (int i = 0; i < 20; i++)
            chunk('c$i', 't1', <String>{'tenant:t1'}, i),
        ],
        <List<double>>[
          for (int i = 0; i < 20; i++) <double>[1, 0],
        ],
      );
      final RagService wide = RagService(
        backend: many,
        config: RagConfig(embedder: FakeEmbedder(), topK: 100),
        scopeOf: (String id) async => RagScope(tenantId: 't1'),
      );
      final ToolResult hit =
          await RagSearchTool(service: wide, scope: RagScope(tenantId: 't1'))
              .call(const ToolContext(ToolCall(
                  name: 'rag_search',
                  arguments: <String, Object?>{'query': 'x', 'limit': 99})));
      final Map<String, Object?> value = hit.value! as Map<String, Object?>;
      expect(value['count'], 15);
      expect(value['hits']! as List<Object?>, hasLength(15));
    });

    test('非法时间戳抛 ToolArgumentException', () async {
      await expectLater(
        open().call(const ToolContext(ToolCall(
            name: 'rag_search',
            arguments: <String, Object?>{'query': 'x', 'from': '昨天'}))),
        throwsA(isA<ToolArgumentException>()),
      );
    });

    test('空结果返回成功且 count 0', () async {
      final ToolResult hit = await open().call(const ToolContext(ToolCall(
          name: 'rag_search',
          arguments: <String, Object?>{'query': 'x', 'session_id': 'nope'})));
      expect(hit.isError, isFalse);
      final Map<String, Object?> value = hit.value! as Map<String, Object?>;
      expect(value['count'], 0);
      expect(value['hits'], isEmpty);
      expect(hit.content, isEmpty);
    });

    test('跨租户隔离：t2 拿不到 t1 数据', () async {
      final RagSearchTool other =
          RagSearchTool(service: service, scope: RagScope(tenantId: 't2'));
      final ToolResult hit = await other.call(const ToolContext(ToolCall(
          name: 'rag_search', arguments: <String, Object?>{'query': '订单号'})));
      expect(hit.isError, isFalse);
      final Map<String, Object?> value = hit.value! as Map<String, Object?>;
      expect(value['count'], 0);
    });
  });
}
