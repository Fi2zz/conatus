import 'dart:math' as math;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_rag/conatus_rag.dart';
import 'package:test/test.dart';

/// 离线 coverage@5 对照：向量检索 vs 词元召回。语料 3 段会话、每段 4 条事实
/// （工号 / 报销 / 请假 / 项目各一条），同义改写拼出 20 个问题。向量侧把同义词组
/// 强制同向，词元侧用 `[a-z0-9]+` + 汉字二元组重叠计数；指标是 gold 子串是否命中。
void main() {
  test('coverage@5：向量检索不弱于词元召回，且 ≥ 0.8', () async {
    final InMemorySessionLog log = InMemorySessionLog();
    await _seed(log, 'a',
        <String>['我的工号是 E-778', '报销了差旅费 1200 元', '十月三日请了年假', '负责凤凰计划']);
    await _seed(log, 'b',
        <String>['员工编号是 F-1024', '费用报销了 800 元', '十月五日请了病假', '负责北斗任务']);
    await _seed(
        log, 'c', <String>['编号是 G-55', '报销了办公用品 300 元', '十月一日休了年假', '负责飞鹰项目']);

    final InMemoryRagBackend backend = InMemoryRagBackend();
    final RagService service = RagService(
      backend: backend,
      config: RagConfig(
        embedder: _FixtureEmbedder(),
        chunkChars: _factWidth + 4,
        overlapChars: 0,
        maxChunkChars: 64,
      ),
      scopeOf: (String id) async => RagScope(tenantId: 't1'),
      log: log,
    );
    await service.ingestAll();

    final List<RagChunk> chunks = backend.snapshot().chunks;
    final RagScope scope = RagScope(tenantId: 't1');
    final List<_Question> questions = _questions();

    int rag = 0;
    int kw = 0;
    for (final _Question q in questions) {
      final String block =
          await service.evidenceBlock(q.query, scope, limit: 5);
      if (block.contains(q.gold)) rag++;
      if (_keywordTop(chunks, q.query, 5).contains(q.gold)) kw++;
    }

    final double ragCoverage = rag / questions.length;
    final double keywordCoverage = kw / questions.length;
    print('coverage@5 rag=${ragCoverage.toStringAsFixed(2)} '
        'keyword=${keywordCoverage.toStringAsFixed(2)}');

    expect(ragCoverage, greaterThanOrEqualTo(keywordCoverage));
    expect(ragCoverage, greaterThanOrEqualTo(0.8));
  });
}

/// 每条事实正文补齐到的宽度；事件文本前缀「用户：」长 3，加 1 个换行符。
const int _factWidth = 16;

Future<void> _seed(
  InMemorySessionLog log,
  String id,
  List<String> facts,
) async {
  for (int i = 0; i < facts.length; i++) {
    await log.append(SessionEvent.create(
      sessionId: id,
      seq: 0,
      type: kUserMessageEvent,
      time: DateTime.utc(2026, 10, 1 + i),
      data: <String, Object?>{'text': facts[i].padRight(_factWidth)},
    ));
  }
}

/// 同义词组 → 维度下标（组下标即维度）；命中置 1（叠加），全未命中落到 hash 维。
class _FixtureEmbedder implements Embedder {
  static const List<List<String>> _groups = <List<String>>[
    <String>['工号', '员工编号', '编号', '工牌号', '工号牌'],
    <String>['报销', '费用报销', '差旅费', '报销款', '垫付'],
    <String>['请假', '年假', '病假', '休假', '假期'],
    <String>['项目', '计划', '任务', '课题', '工程'],
  ];

  @override
  String get model => 'fixture';

  @override
  int get dimension => 8;

  @override
  Future<List<double>> embed(String text) async => _embed(text);

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async =>
      <List<double>>[for (final String t in texts) _embed(t)];

  @override
  void dispose() {}

  List<double> _embed(String text) {
    final List<double> v = List<double>.filled(dimension, 0);
    bool hit = false;
    for (int g = 0; g < _groups.length; g++) {
      if (_groups[g].any((String w) => text.contains(w))) {
        v[g] = 1;
        hit = true;
      }
    }
    if (!hit) {
      int sum = 0;
      for (final int code in text.runes) {
        sum += code;
      }
      v[sum % dimension] = 1;
    }
    return _normalize(v);
  }

  List<double> _normalize(List<double> v) {
    double norm = 0;
    for (final double x in v) {
      norm += x * x;
    }
    if (norm == 0) return v;
    final double scale = math.sqrt(norm);
    return <double>[for (final double x in v) x / scale];
  }
}

class _Question {
  const _Question(this.query, this.gold);

  final String query;
  final String gold;
}

List<_Question> _questions() => <_Question>[
      // 改写（5）：同义词组重述单条事实。
      const _Question('我的工牌号是多少', 'E-778'),
      const _Question('报销款一共多少钱', '1200'),
      const _Question('我的假期是哪天', '十月三日'),
      const _Question('手头的课题叫什么', '北斗任务'),
      const _Question('垫付的金额是多少', '300'),
      // 多跳（5）：答案需要跨会话合并两条事实。
      const _Question('谁报销的金额最多', '1200'),
      const _Question('谁的工号数字最大', 'F-1024'),
      const _Question('谁请假的日期最晚', '十月五日'),
      const _Question('报销最少的金额是多少', '300'),
      const _Question('工号数字最小的是多少', 'G-55'),
      // 时序（5）：相对先后决定答案。
      const _Question('谁最早请假', '十月一日'),
      const _Question('谁最后请假', '十月五日'),
      const _Question('请假日期排在中间的是哪天', '十月三日'),
      const _Question('请了病假的是哪天', '十月五日'),
      const _Question('年假最早的是哪天', '十月一日'),
      // 跨会话（5）：答案来自两条会话的事实。
      const _Question('报销最多的人负责什么任务', '凤凰计划'),
      const _Question('工号最大的人休了什么假', '十月五日'),
      const _Question('报销最多和最少分别是多少', '1200'),
      const _Question('工号最大和最小的数字分别是', 'F-1024'),
      const _Question('请假最早和最晚的日期分别是', '十月一日'),
    ];

/// 词元召回：`[a-z0-9]+` + 汉字二元组重叠计数，取 top-k 拼接文本。
String _keywordTop(List<RagChunk> chunks, String query, int k) {
  final List<RagChunk> ranked = List<RagChunk>.from(chunks);
  ranked.sort((RagChunk a, RagChunk b) {
    final int byScore =
        _overlap(query, b.text).compareTo(_overlap(query, a.text));
    if (byScore != 0) return byScore;
    return a.id.compareTo(b.id);
  });
  return <String>[for (final RagChunk c in ranked.take(k)) c.text].join('\n');
}

int _overlap(String query, String text) =>
    _tokens(query).intersection(_tokens(text)).length;

Set<String> _tokens(String text) {
  final Set<String> tokens = <String>{};
  for (final RegExpMatch m
      in RegExp('[a-z0-9]+').allMatches(text.toLowerCase())) {
    tokens.add(m.group(0)!);
  }
  final List<int> runes = text.runes.toList();
  for (int i = 0; i + 1 < runes.length; i++) {
    if (_isCjk(runes[i]) && _isCjk(runes[i + 1])) {
      tokens.add(String.fromCharCodes(<int>[runes[i], runes[i + 1]]));
    }
  }
  return tokens;
}

bool _isCjk(int code) => code >= 0x4E00 && code <= 0x9FFF;
